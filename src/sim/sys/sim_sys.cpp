// sim_sys: tb_sys (msx_system + msx_video + SRAM model) under verilator.
//
//   sim_sys --rom FILE:ADDR ... [--cart FILE] [--cart-b FILE] [--bios FILE] [--mapper-a N]
//           [--pal] [--frames N] [--ppm OUT] [--every N] [--key F:CODE[,CODE]] [--hash]
//
// The ROMs go in through the ROM loader of the mcu (rom_active, one byte every 12 clocks, as a
// burst at 32 MHz), the files through the file loader (FL slot 0 = cartridge A, 1 = B, 2 = BIOS).
// The clocks: a tick of the VCO (600 MHz), clk every 14 ticks (42.857 MHz), clk_vga every 24
// (25.0 MHz), as the PLL of the tops. A frame is a vsync of the 640 x 480 output; --ppm writes the
// output frame after the last one (or every N with --every, OUT-<n>.ppm). --hash prints a
// CRC-32 of each written frame. --key F:CODE sends the PS/2 set 2 codes (hex) at frame F, a
// release (F0 code) 5 frames later.
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

static int dbg_b = -1;
static bool dbg = getenv("SIM_DBG") != 0;
static void tick() {
	ticks++;
	bool step = false;
	if (ticks % 7 == 0) { top->clk = !top->clk; step = true; if (top->clk) clks++; }
	bool vga_rise = false;
	if (ticks % 12 == 0) { top->clk_vga = !top->clk_vga; step = true; vga_rise = top->clk_vga; }
	if (step) top->eval();
	if (dbg && top->dbg_border != dbg_b) { printf("frame %d y %d border %d\n", frames, top->dbg_y, top->dbg_border); dbg_b = top->dbg_border; }
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
	bool pal = false, hash = false;
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
	top->eval();
	clk_cycles(100);
	for (auto &r : roms) rom_load(load(r.first.c_str()), r.second);
	if (!bios.empty()) file_load(load(bios.c_str()), 2);
	if (!cart_a.empty()) file_load(load(cart_a.c_str()), 0);
	if (!cart_b.empty()) file_load(load(cart_b.c_str()), 1);
	clk_cycles(100);
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
	delete top;
	return 0;
}
