#include "Vosborne1.h"
#include "Vosborne1___024root.h"
#include "verilated.h"
#include "verilated_save.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include <string>

static Vosborne1 *top;
static uint64_t clk_cnt = 0;
static std::vector<uint8_t> img[2];
static std::string imgname[2];

// framebuffer
static uint8_t fb[260][1024];
static int fx=0, fy=0, frames=0;
static int old_hs=0, old_vs=0;

static void save_frame(const char *fn) {
    FILE *f=fopen(fn,"wb"); fprintf(f,"P5\n1024 260\n255\n");
    fwrite(fb,1,sizeof(fb),f); fclose(f);
}


static void tick() {
    // clk_vid = 2 x clk_sys, flancos de subida alineados
    auto cap=[&](){
        if (top->ce_pix) {
            if (top->hsync && !old_hs) { fx=0; fy++; }
            if (top->vsync && !old_vs) { fy=0; frames++; }
            old_hs=top->hsync; old_vs=top->vsync;
            if (fx<1024 && fy<260) fb[fy][fx]=top->video;
            fx++;
        }
    };
    top->clk_sys = 1; top->clk_vid = 1; top->eval(); cap();
    top->clk_vid = 0; top->eval();
    top->clk_vid = 1; top->eval(); cap();
    top->clk_sys = 0; top->clk_vid = 0; top->eval();
    clk_cnt++;
}

static int sd_state[2]={0,0}; static int sd_cnt[2]; static int sd_wrmode[2]; static uint32_t sd_lbav[2];

static int trace=0; static int rd_pend=0; static int rd_addr=0; static int old_mrd=0;
static void do_trace() {
    if(!trace) return;
    auto r=top->rootp;
    if (r->osborne1__DOT__cs_fdc && r->osborne1__DOT__mem_wr_stb)
        printf("%.6f FDC W %d <= %02X  pa=%02X pb=%02X\n", clk_cnt/31948800.0, r->osborne1__DOT__addr&3, r->osborne1__DOT__cpu_dout, r->osborne1__DOT__vpia_pa, r->osborne1__DOT__vpia_pb);
    { static int na=0; static int ordrf=0; int rd=r->osborne1__DOT__acia__DOT__rdrf; if(rd!=ordrf){ordrf=rd; printf("%.6f ACIA RDRF=%d\n", clk_cnt/31948800.0, rd);} 
      if (r->osborne1__DOT__cs_acia && (r->osborne1__DOT__mem_wr_stb) && na++<200) printf("%.6f ACIA W %d <= %02X\n", clk_cnt/31948800.0, r->osborne1__DOT__addr&1, r->osborne1__DOT__cpu_dout);
      static int nr=0; if (r->osborne1__DOT__cs_acia && r->osborne1__DOT__mem_rd_stb && clk_cnt>31948800.0*7.95 && nr++<60) printf("%.6f ACIA R %d A=%04X\n", clk_cnt/31948800.0, r->osborne1__DOT__addr&1, r->osborne1__DOT__addr); }
    { static int ns=0; if (r->osborne1__DOT__cs_spac && r->osborne1__DOT__mem_wr_stb && ns++<50) printf("%.6f SPAC W <= %02X\n", clk_cnt/31948800.0, r->osborne1__DOT__cpu_dout);
      static int ns2=0; if (r->osborne1__DOT__cs_spac && r->osborne1__DOT__mem_rd_stb && ns2++<20) printf("%.6f SPAC R\n", clk_cnt/31948800.0); }
    static int lastdin=0; static int oldrom=-1; static int nio=0, nint=0;
    if (r->osborne1__DOT__io_wr_stb && (r->osborne1__DOT__addr&2)==0 && nio++<40) printf("%.6f IO W %04X <= %02X\n", clk_cnt/31948800.0, r->osborne1__DOT__addr, r->osborne1__DOT__cpu_dout);
    if (r->osborne1__DOT__inta_stb && nint++<10) printf("%.6f INTA rom=%d ub4a=%d\n", clk_cnt/31948800.0, r->osborne1__DOT__rom_mode, r->osborne1__DOT__ub4a);
    if (r->osborne1__DOT__rom_mode != oldrom) { oldrom=r->osborne1__DOT__rom_mode; static int nr=0; if(nr++<40) printf("%.6f ROMMODE=%d A=%04X\n", clk_cnt/31948800.0, oldrom, r->osborne1__DOT__addr); }
    if (r->osborne1__DOT__cs_fdc && r->osborne1__DOT__mem_rd_stb) { rd_pend=1; rd_addr=r->osborne1__DOT__addr&3; }
    if (rd_pend && r->osborne1__DOT__mem_rd) lastdin=r->osborne1__DOT__cpu_din;
    if (rd_pend && !r->osborne1__DOT__mem_rd) { rd_pend=0; if(trace>1 || rd_addr!=3) printf("%.6f FDC R %d => %02X\n", clk_cnt/31948800.0, rd_addr, lastdin); }
}
static double ftrace_from=1e9, ftrace_to=0; static FILE *ff=nullptr;
static void sd_service() {
    do_trace();
    { double t=clk_cnt/31948800.0; if (t>=ftrace_from && t<ftrace_to && top->rootp->osborne1__DOT__fetch_stb) { if(!ff) ff=fopen("fetch.txt","w"); fprintf(ff,"%04X %d\n", top->rootp->osborne1__DOT__addr, top->rootp->osborne1__DOT__rom_mode);} }
    for (int d=0; d<2; d++) {
        switch (sd_state[d]) {
        case 0:
            if ((top->sd_rd>>d)&1 || (top->sd_wr>>d)&1) {
                sd_wrmode[d]=(top->sd_wr>>d)&1; sd_lbav[d]=top->sd_lba[d];
                top->sd_ack |= (1<<d); sd_state[d]=1; sd_cnt[d]=0;
            }
            break;
        case 1: { // transfer 512 bytes, one byte per 4 clocks
            int i=sd_cnt[d];
            if (!sd_wrmode[d]) {
                if ((i&3)==0 && i/4<512) {
                    size_t o=(size_t)sd_lbav[d]*512+i/4;
                    top->sd_buff_addr=i/4; top->sd_buff_dout = o<img[d].size()?img[d][o]:0xE5; top->sd_buff_wr=1;
                } else top->sd_buff_wr=0;
            } else {
                if ((i&3)==0 && i/4<512) top->sd_buff_addr=i/4;
                if ((i&3)==3 && i/4<512) { size_t o=(size_t)sd_lbav[d]*512+i/4; if(o<img[d].size()) img[d][o]=top->sd_buff_din[d]; }
            }
            if (++sd_cnt[d] > 512*4+100) { top->sd_ack &= ~(1<<d); top->sd_buff_wr=0; sd_state[d]=2; sd_cnt[d]=0; }
            break; }
        case 2:
            if (++sd_cnt[d] > 100) sd_state[d]=0;
            break;
        }
    }
}

static void dump_text() {
    auto r = top->rootp;
    int sy = r->osborne1__DOT__scroll_y;
    int pa = r->osborne1__DOT__video_pia__DOT__ora;
    int col0 = ((pa>>1)+0x0B)&0x7f;
    int w=52;
    if (r->osborne1__DOT__sp_hires) { w=104; col0=(((pa>>1)&0x60)+(r->osborne1__DOT__sp_hcleft?0x09:0x01)+0x17)&0x7f; }
    printf("---- screen (scroll_y=%d col0=%d rom_mode=%d cols=%d) ----\n", sy, col0, r->osborne1__DOT__rom_mode, w);
    for (int y=0;y<24;y++){
        char line[110]; int row=((sy+y)&31)<<7;
        for (int x=0;x<w;x++){ int c=r->osborne1__DOT__ram[0xF000|row|((col0+x)&0x7f)]&0x7f; line[x]=(c>=32&&c<127)?c:(c?'#':' ');}
        line[w]=0; printf("|%s|\n",line);
    }
}

// ---- terminal serie virtual ----
static int ser_bitclk() { // ciclos de clk_sys por bit segun puente 0 y divisor de la ACIA
    int cr = top->rootp->osborne1__DOT__acia__DOT__cr;
    int div = (cr&3)==0 ? 1 : (cr&3)==1 ? 16 : 64;
    return 1664*div;
}
static void ser_frame_fmt(int &bits, int &par, int &odd, int &stops) {
    int w=(top->rootp->osborne1__DOT__acia__DOT__cr>>2)&7;
    static const int B[8]={7,7,7,7,8,8,8,8}, P[8]={1,1,1,1,0,0,1,1}, O[8]={0,1,0,1,0,0,0,1}, S[8]={2,2,1,1,2,1,1,1};
    bits=B[w]; par=P[w]; odd=O[w]; stops=S[w];
}
static std::string ser_out; static int stx_state=0; static uint64_t stx_next=0; static int stx_bit=0, stx_val=0, old_txd=1;
static void ser_tx_monitor() {
    int txd = top->ser_txd;
    if (stx_state==0) { if (old_txd && !txd) { stx_state=1; stx_next=clk_cnt+ser_bitclk()*3/2; stx_bit=0; stx_val=0; } }
    else if (clk_cnt>=stx_next) {
        int bits,par,odd,stops; ser_frame_fmt(bits,par,odd,stops);
        if (stx_bit<bits) { stx_val|=txd<<stx_bit; stx_bit++; stx_next+=ser_bitclk(); }
        else { char c=stx_val&0x7f; ser_out.push_back(c); stx_state=0; }
    }
    old_txd=txd;
}
static std::vector<std::pair<double,std::string>> ser_script; static size_t ss_i=0; static std::string ser_pend; static size_t sp_i=0;
static std::vector<int> srx_frame; static size_t srx_pos=0; static uint64_t srx_next=0;
static void ser_rx_driver() {
    double t=clk_cnt/31948800.0;
    if (ss_i<ser_script.size() && t>=ser_script[ss_i].first && sp_i>=ser_pend.size() && srx_pos>=srx_frame.size()) { ser_pend=ser_script[ss_i].second; sp_i=0; ss_i++; }
    if (srx_pos>=srx_frame.size()) {
        top->ser_rxd=1;
        if (sp_i<ser_pend.size() && clk_cnt>=srx_next) {
            int bits,par,odd,stops; ser_frame_fmt(bits,par,odd,stops);
            int c=(unsigned char)ser_pend[sp_i++]; if(c=='\n') c='\r';
            srx_frame.clear(); srx_frame.push_back(0); int p=0;
            for(int i=0;i<bits;i++){ int b=(c>>i)&1; p^=b; srx_frame.push_back(b);} 
            if(par) srx_frame.push_back(p^odd);
            for(int i=0;i<stops;i++) srx_frame.push_back(1);
            srx_frame.push_back(1); srx_frame.push_back(1);
            srx_pos=0; srx_next=clk_cnt;
        }
    } else if (clk_cnt>=srx_next) {
        top->ser_rxd=srx_frame[srx_pos++]; srx_next=clk_cnt+ser_bitclk();
        if (srx_pos>=srx_frame.size()) srx_next=clk_cnt+(uint64_t)(31948800*0.02);
    }
}

static int ps2_toggle=0;
static int screenpac=0;
static std::string save_fn, load_fn;
static void key(int code, bool ext, bool press) {
    ps2_toggle^=1;
    top->ps2_key = (ps2_toggle<<10) | (press<<9) | (ext<<8) | code;
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    top = new Vosborne1;
    double secs = 6.0;
    std::vector<std::pair<double,std::string>> script; // time, keys
    for (int i=1;i<argc;i++){
        if(!strcmp(argv[i],"-a")) imgname[0]=argv[++i];
        else if(!strcmp(argv[i],"-b")) imgname[1]=argv[++i];
        else if(!strcmp(argv[i],"-v")) trace=atoi(argv[++i]);
        else if(!strcmp(argv[i],"-f")) { ftrace_from=atof(argv[++i]); ftrace_to=atof(argv[++i]); }
        else if(!strcmp(argv[i],"-s")) { double t=atof(argv[++i]); ser_script.push_back({t,argv[++i]}); }
        else if(!strcmp(argv[i],"-p")) screenpac=1;
        else if(!strcmp(argv[i],"-save")) save_fn=argv[++i];
        else if(!strcmp(argv[i],"-load")) load_fn=argv[++i];
        else if(!strcmp(argv[i],"-t")) secs=atof(argv[++i]);
        else if(!strcmp(argv[i],"-k")) { double t=atof(argv[++i]); script.push_back({t,argv[++i]}); }
    }
    for (int d=0;d<2;d++) if(!imgname[d].empty()){ FILE*f=fopen(imgname[d].c_str(),"rb"); fseek(f,0,SEEK_END); long n=ftell(f); rewind(f); img[d].resize(n); fread(img[d].data(),1,n,f); fclose(f);}    
    top->screenpac=screenpac;
    top->serial_cfg=0; top->ser_rxd=1; top->ser_cts_n=0; top->ser_dcd_n=0; top->ser_ri_n=1;
    if (!load_fn.empty()) {
        VerilatedRestore is; is.open(load_fn.c_str()); is >> *top;
        uint64_t c; is.read(&c, sizeof(c)); clk_cnt=c; is.read(&ps2_toggle, sizeof(ps2_toggle)); is.close();
        for (int d=0;d<2;d++) if(!imgname[d].empty()) { std::string o=imgname[d]+".out"; FILE*f=fopen(o.c_str(),"rb"); if(f){ fread(img[d].data(),1,img[d].size(),f); fclose(f);} }
        top->screenpac=screenpac;
    } else {
    top->reset=1; for(int i=0;i<100;i++) tick(); top->reset=0;
    // mount
    for (int d=0;d<2;d++) if(img[d].size()) {
        top->img_size=img[d].size(); top->img_readonly=0; top->img_mounted=1<<d; for(int i=0;i<16;i++) tick(); top->img_mounted=0; for(int i=0;i<16;i++) tick();
    }
    }
    const double clk=31948800.0;
    uint64_t end=(uint64_t)(secs*clk);
    size_t si=0; std::string pending; size_t pi=0; uint64_t next_key=0; int kstate=0;
    int last_report=-1;
    // scancode table for ASCII
    auto sc=[&](char ch)->int{ const char*k="abcdefghijklmnopqrstuvwxyz"; static int t[26]={0x1C,0x32,0x21,0x23,0x24,0x2B,0x34,0x33,0x43,0x3B,0x42,0x4B,0x3A,0x31,0x44,0x4D,0x15,0x2D,0x1B,0x2C,0x3C,0x2A,0x1D,0x22,0x35,0x1A};
        if(ch>='a'&&ch<='z') return t[ch-'a']; if(ch>='A'&&ch<='Z') return t[ch-'A'];
        static int dg[10]={0x45,0x16,0x1E,0x26,0x25,0x2E,0x36,0x3D,0x3E,0x46}; if(ch>='0'&&ch<='9') return dg[ch-'0'];
        if(ch=='\n') return 0x5A; if(ch==' ') return 0x29; if(ch=='.') return 0x49; if(ch==':') return 0x4C; if(ch=='\x1b') return 0x76; if(ch=='=') return 0x55; return 0x29; };
    while (clk_cnt < end) {
        tick(); sd_service(); ser_tx_monitor(); ser_rx_driver();
        double t = clk_cnt/clk;
        if (si<script.size() && t>=script[si].first && pi>=pending.size()) { pending=script[si].second; pi=0; si++; next_key=clk_cnt; kstate=0; }
        if (pi<pending.size() && clk_cnt>=next_key) {
            char ch=pending[pi]; bool shift = (ch>='A'&&ch<='Z') || ch==':';
            switch(kstate){
              case 0: if(shift) key(0x12,0,1); kstate=1; break;
              case 1: key(sc(ch),0,1); kstate=2; break;
              case 2: key(sc(ch),0,0); kstate=3; break;
              case 3: if(shift) key(0x12,0,0); kstate=0; pi++; break;
            }
            next_key = clk_cnt + (uint64_t)(clk*0.06);
        }
        int rep=(int)(t*2);
        if (rep!=last_report) { last_report=rep; }
    }
    dump_text();
    { FILE*f=fopen("ram.bin","wb"); for(int i=0;i<65536;i++) fputc(top->rootp->osborne1__DOT__ram[i],f); fclose(f);}
    save_frame("frame.pgm");
    printf("---- serie TX ----\n%s\n------------------\n", ser_out.c_str());
    printf("frames=%d PC=%04x\n", frames, 0);
    for (int d=0;d<2;d++) if(img[d].size()){ std::string o=imgname[d]+".out"; FILE*f=fopen(o.c_str(),"wb"); fwrite(img[d].data(),1,img[d].size(),f); fclose(f);}    
    if (!save_fn.empty()) { VerilatedSave os; os.open(save_fn.c_str()); os << *top; uint64_t c=clk_cnt; os.write(&c,sizeof(c)); os.write(&ps2_toggle,sizeof(ps2_toggle)); os.close(); }
    delete top; return 0;
}
