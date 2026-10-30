// sim_sys: tb_sys (msx_system + msx_video + SRAM model) under verilator.
//
//   sim_sys --rom FILE:ADDR ... [--cart FILE] [--cart-b FILE] [--bios FILE] [--mapper-a N]
//           [--pal] [--frames N] [--ppm OUT] [--every N] [--key F:CODE[,CODE]] [--hash]
//           [--disk FILE.dsk [--fdd-latency MS] [--fdd-drop N] [--save-disk OUT]]
//
// The ROMs go in through the ROM loader of the mcu (rom_active, one byte every 12 clocks, as a
// burst at 32 MHz), the files through the file loader (FL slot 0 = cartridge A, 1 = B, 2 = BIOS).
// The clocks: a tick of the VCO (600 MHz), clk every 14 ticks (42.857 MHz), clk_vga every 24
// (25.0 MHz), as the PLL of the tops. A frame is a vsync of the 640 x 480 output; --ppm writes the
// output frame after the last one (or every N with --every, OUT-<n>.ppm). --hash prints a
// CRC-32 of each written frame. --key F:CODE sends the PS/2 set 2 codes (hex) at frame F, a
// release (F0 code) 5 frames later. --disk: slot 1 is the disk drive with this image on a model of the
// file mounter of the firmware (mcu_clk); SIM_FDD=1 logs its requests.
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>
#include <map>
#include "Vtb_sys.h"
#include "verilated.h"

static Vtb_sys *top;
static uint64_t ticks = 0;
static uint64_t clks = 0;

// output frame capture (clk_vga)
static std::vector<uint8_t> frame(640 * 480 * 3);
static int fx = 0, fy = 0, frames = 0;
static bool prev_hs = false, prev_vs = false, prev_de = false;

static void on_vga() {
	bool hs = top->hs, vs = top->vs, de = top->de;
	if (de) {
		if (fx < 640 && fy < 480) {
			uint32_t c = top->rgb;
			uint8_t *p = &frame[(fy * 640 + fx) * 3];
			p[0] = c >> 16; p[1] = c >> 8; p[2] = c;
		}
		fx++;
	}
	if (!de && prev_de) { fx = 0; fy++; }
	if (vs && !prev_vs) { fy = 0; fx = 0; frames++; }
	prev_hs = hs; prev_vs = vs; prev_de = de;
}

static int isr_cnt = 0; static bool prev_isr = false;
static int dbg_b = -1, dbg_k = -1, dbg_kb = -1, dbg_row = -1;
static int kbdbg_from = getenv("SIM_KBDBG") ? atoi(getenv("SIM_KBDBG")) : -1;
static bool dbg = getenv("SIM_DBG") != 0;
// ---- the file mounter of the firmware (docs/protocol.md section 6), on the IMG_* ports of kg_mcu:
// the requests of img_sdc come as img_q words (acked one clock), a read is answered after
// fdd_latency clk with 512 bytes (one per 11 clk, a burst at 32 MHz), the sum, the result; a write
// is taken with its bytes and sum and answered after fdd_latency.
static std::vector<uint8_t> disk;
static int fdd_latency = 0;           // clk
static int fdd_drop = -1;             // the number of the request whose answer is lost
static int fdd_reqs = 0;
static uint64_t fdd_busy_clk = 0;     // clk between a request and its answer, summed
static uint32_t mcu_lba = 0;
static int mcu_lba_bytes = 0;
static int mcu_op = 0;                // 1 read, 2 write in progress
static int64_t mcu_wait = -1;         // clk until the answer
static int mcu_pos = -1;              // the next byte of a read answer
static int mcu_gap = 0;
static uint8_t mcu_wbuf[512];
static int mcu_wcnt = 0, mcu_bank = 0;
static uint16_t mcu_wsum = 0;
static int mcu_wsum_parts = 0;
static uint64_t mcu_req_clk = 0;
static bool fdd_log = getenv("SIM_FDD") != 0;
static int mount_at = -1;             // clk to mount the disk (pulse img_mounted[0])

static void mcu_answer(bool ok) {
	top->img_result = ok ? 1 : 2;
	top->img_result_wr = 1;
}

static void mcu_clk() {
	// pulses of one clock end here
	top->img_q_ack = 0;
	top->img_data_wr = 0;
	top->img_result_wr = 0;
	top->img_mounted = 0;
	if (mount_at >= 0 && (int64_t)clks >= mount_at) {
		top->img_size = disk.size();
		top->img_mounted = 1;
		mount_at = -1;
		if (fdd_log) printf("mcu: mount %zu bytes\n", disk.size());
	}
	if (top->img_q_wr && !top->img_q_ack) {
		uint32_t w = top->img_q_di;
		uint8_t c = w >> 16, a = w >> 8, d = w;
		top->img_q_ack = 1;
		if (c == 0x42) {
			if (a == 0) { mcu_lba = 0; mcu_lba_bytes = 0; }
			mcu_lba |= (uint32_t)d << (8 * a);
			mcu_lba_bytes++;
		}
		else if (c == 0x43) {
			fdd_reqs++;
			mcu_op = d;
			mcu_req_clk = clks;
			mcu_wcnt = 0; mcu_wsum_parts = 0; mcu_wsum = 0;
			if (fdd_log) printf("mcu: %s lba %u (request %d)\n", d == 1 ? "read" : "write", mcu_lba, fdd_reqs);
			if (fdd_reqs == fdd_drop) { if (fdd_log) printf("mcu: request %d lost\n", fdd_reqs); mcu_op = 0; }
			else if (d == 1) mcu_wait = fdd_latency;
		}
		else if (c == 0x44 && mcu_op == 2) {
			if (a == 0) mcu_bank = d & 1;
			else if (a == 0x10) { mcu_wsum = (mcu_wsum & 0xFF00) | d; mcu_wsum_parts++; }
			else if (a == 0x11) { mcu_wsum = (mcu_wsum & 0x00FF) | (d << 8); mcu_wsum_parts++; if (mcu_wsum_parts == 2) mcu_wait = fdd_latency; }
		}
		else if (c == 0x45 && mcu_op == 2) {
			mcu_wbuf[mcu_bank * 256 + a] = d;
			mcu_wcnt++;
		}
	}
	if (mcu_wait > 0) mcu_wait--;
	else if (mcu_wait == 0) {
		mcu_wait = -1;
		if (mcu_op == 1) { mcu_pos = 0; mcu_gap = 0; }
		else if (mcu_op == 2) {
			uint16_t sum = 0;
			for (int i = 0; i < 512; i++) sum += mcu_wbuf[i];
			bool ok = mcu_wcnt == 512 && sum == mcu_wsum && (size_t)(mcu_lba + 1) * 512 <= disk.size();
			if (ok) memcpy(&disk[mcu_lba * 512], mcu_wbuf, 512);
			if (fdd_log) printf("mcu: write lba %u %s\n", mcu_lba, ok ? "done" : "ERROR");
			fdd_busy_clk += clks - mcu_req_clk;
			mcu_answer(ok);
			mcu_op = 0;
		}
	}
	if (mcu_pos >= 0) {
		bool in = (size_t)(mcu_lba + 1) * 512 <= disk.size() && mcu_lba_bytes == 4;
		if (mcu_pos < 512) {
			if (in && ++mcu_gap >= 11) {
				mcu_gap = 0;
				top->img_data_addr = mcu_pos;
				top->img_data = disk[mcu_lba * 512 + mcu_pos];
				top->img_data_wr = 1;
				mcu_pos++;
			}
			if (!in) mcu_pos = 512;
		}
		else {
			uint16_t sum = 0;
			if (in) for (int i = 0; i < 512; i++) sum += disk[mcu_lba * 512 + i];
			top->img_sum = sum;
			mcu_answer(in);
			fdd_busy_clk += clks - mcu_req_clk;
			mcu_pos = -1;
			mcu_op = 0;
		}
	}
}

static void tick() {
	ticks++;
	bool step = false;
	bool clk_rise = false;
	if (ticks % 7 == 0) { top->clk = !top->clk; step = true; if (top->clk) { clks++; clk_rise = true; } }
	bool vga_rise = false;
	if (ticks % 12 == 0) { top->clk_vga = !top->clk_vga; step = true; vga_rise = top->clk_vga; }
	if (step) top->eval();
	if (clk_rise && !disk.empty()) mcu_clk();
	if (dbg && top->dbg_border != dbg_b) { printf("frame %d y %d border %d\n", frames, top->dbg_y, top->dbg_border); dbg_b = top->dbg_border; }
	{ bool isr = !top->cpu_m1_n && top->cpu_a == 0x38; if (isr && !prev_isr) isr_cnt++; prev_isr = isr; }
	if (kbdbg_from >= 0 && frames >= kbdbg_from && top->dbg_kb_row != dbg_row) { dbg_row = top->dbg_kb_row; printf("frame %d row %d kb %02x\n", frames, dbg_row, top->dbg_kb); }
	if (dbg && top->dbg_ps2_key != dbg_k) { printf("frame %d ps2_key %03x\n", frames, top->dbg_ps2_key); dbg_k = top->dbg_ps2_key; }
	if (dbg && top->dbg_kb != 0xFF && ((top->dbg_kb_row << 8) | top->dbg_kb) != dbg_kb) { dbg_kb = (top->dbg_kb_row << 8) | top->dbg_kb; printf("frame %d kb row %d = %02x\n", frames, top->dbg_kb_row, top->dbg_kb); }
	if (vga_rise) on_vga();
}

static void clk_cycles(int n) {
	uint64_t end = clks + n;
	while (clks < end) tick();
}

static std::vector<uint8_t> load(const char *fn) {
	FILE *f = fopen(fn, "rb");
	if (!f) { perror(fn); exit(1); }
	std::vector<uint8_t> d;
	int c;
	while ((c = fgetc(f)) != EOF) d.push_back(c);
	fclose(f);
	return d;
}

static void rom_load(const std::vector<uint8_t> &d, uint32_t addr) {
	top->rom_active = 1;
	for (size_t i = 0; i < d.size(); i++) {
		top->rom_addr = addr + i;
		top->rom_data = d[i];
		top->rom_wr = 1;
		clk_cycles(1);
		top->rom_wr = 0;
		clk_cycles(11);
	}
	clk_cycles(4);
	top->rom_active = 0;
}

static void file_load(const std::vector<uint8_t> &d, int slot) {
	top->file_slot = slot;
	top->file_active = 1;
	clk_cycles(4);
	for (size_t i = 0; i < d.size(); i++) {
		top->file_addr = i;
		top->file_data = d[i];
		top->file_wr = 1;
		clk_cycles(1);
		top->file_wr = 0;
		clk_cycles(11);
	}
	clk_cycles(4);
	top->file_active = 0;
}

static uint32_t crc32(const uint8_t *p, size_t n) {
	uint32_t c = 0xFFFFFFFF;
	for (size_t i = 0; i < n; i++) {
		c ^= p[i];
		for (int k = 0; k < 8; k++) c = (c >> 1) ^ (0xEDB88320 & -(c & 1));
	}
	return ~c;
}

static void write_ppm(const std::string &fn) {
	FILE *f = fopen(fn.c_str(), "wb");
	if (!f) { perror(fn.c_str()); exit(1); }
	fprintf(f, "P6\n640 480\n255\n");
	fwrite(frame.data(), 1, frame.size(), f);
	fclose(f);
}

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	top = new Vtb_sys;
	std::vector<std::pair<std::string, uint32_t>> roms;
	std::string cart_a, cart_b, bios, ppm;
	int nframes = 60, every = 0, mapper_a = 0;
	bool pal = false, hash = false, fdd = false;
	std::string save_disk;
	std::map<int, std::vector<int>> keys;
	for (int i = 1; i < argc; i++) {
		std::string a = argv[i];
		auto next = [&]() { if (i + 1 >= argc) { fprintf(stderr, "%s: value?\n", a.c_str()); exit(1); } return std::string(argv[++i]); };
		if (a == "--rom") { std::string v = next(); size_t c = v.rfind(':'); roms.push_back({v.substr(0, c), (uint32_t)strtoul(v.c_str() + c + 1, 0, 0)}); }
		else if (a == "--cart") cart_a = next();
		else if (a == "--cart-b") cart_b = next();
		else if (a == "--bios") bios = next();
		else if (a == "--mapper-a") mapper_a = atoi(next().c_str());
		else if (a == "--pal") pal = true;
		else if (a == "--disk") { disk = load(next().c_str()); fdd = true; }
		else if (a == "--fdd-latency") fdd_latency = atof(next().c_str()) * 42857;
		else if (a == "--fdd-drop") fdd_drop = atoi(next().c_str());
		else if (a == "--save-disk") save_disk = next();
		else if (a == "--frames") nframes = atoi(next().c_str());
		else if (a == "--ppm") ppm = next();
		else if (a == "--every") every = atoi(next().c_str());
		else if (a == "--hash") hash = true;
		else if (a == "--key") {
			std::string v = next(); size_t c = v.find(':');
			int f = atoi(v.substr(0, c).c_str());
			std::string codes = v.substr(c + 1);
			size_t p = 0;
			while (p < codes.size()) {
				size_t q = codes.find(',', p); if (q == std::string::npos) q = codes.size();
				keys[f].push_back(strtol(codes.substr(p, q - p).c_str(), 0, 16));
				p = q + 1;
			}
		}
		else if (a[0] == '+') ;
		else { fprintf(stderr, "unknown argument %s\n", a.c_str()); return 1; }
	}
	top->clk = 0; top->clk_vga = 0;
	top->reset = 1;
	top->mapper_a = mapper_a; top->mapper_b = 0;
	top->pal = pal;
	top->joy_l = 0;
	top->fdd = fdd;
	top->eval();
	clk_cycles(100);
	for (auto &r : roms) rom_load(load(r.first.c_str()), r.second);
	if (!bios.empty()) file_load(load(bios.c_str()), 2);
	if (!cart_a.empty()) file_load(load(cart_a.c_str()), 0);
	if (!cart_b.empty()) file_load(load(cart_b.c_str()), 1);
	if (fdd) mount_at = clks + 1000;
	clk_cycles(2000);
	top->reset = 0;
	int f0 = frames;
	std::map<int, std::vector<int>> release;
	bool upd = false;
	int last = -1;
	while (frames - f0 < nframes) {
		tick();
		int f = frames - f0;
		if (f != last) {
			last = f;
			if (getenv("SIM_ISR")) { printf("frame %d isr %d\n", f, isr_cnt); isr_cnt = 0; }
			auto send = [&](int code) {
				top->kb_scancode = code; upd = !upd; top->kb_scancode_upd = upd;
				clk_cycles(2000);
			};
			if (keys.count(f)) {
				for (int c : keys[f]) { if (c >= 0xE0) send(c); else { send(c); release[f + 5].push_back(c); } }
			}
			if (release.count(f)) for (int c : release[f]) { send(0xF0); send(c); }
			if (f > 0 && ((every && f % every == 0) || f == nframes)) {
				if (hash) printf("frame %d crc %08x\n", f, crc32(frame.data(), frame.size()));
				if (!ppm.empty()) write_ppm(every ? ppm + "-" + std::to_string(f) + ".ppm" : ppm);
			}
		}
	}
	printf("%d frames, %llu clk\n", nframes, (unsigned long long)clks);
	if (fdd) printf("fdd: %d requests, %.1f ms waiting for the mcu\n", fdd_reqs, fdd_busy_clk / 42857.0);
	if (!save_disk.empty()) { FILE *f = fopen(save_disk.c_str(), "wb"); fwrite(disk.data(), 1, disk.size(), f); fclose(f); }
	delete top;
	return 0;
}
