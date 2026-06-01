"""
Generate all benchmark figures for ECE268 lightweight cipher project.
Run from project root: python3 figures/generate_figures.py
Output: figures/*.png  (dark background, 16:9 aspect, 150 dpi)
"""

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import numpy as np
import os

OUT = os.path.join(os.path.dirname(__file__))
os.makedirs(OUT, exist_ok=True)

plt.style.use('dark_background')

C = {
    'PRESENT-80':   '#ff7f0e',
    'SPECK-64/128': '#00bfff',
    'AES-128':      '#00c853',
}
ACCENT = '#ffffff'
GRID   = '#333333'

def savefig(name):
    path = os.path.join(OUT, name)
    plt.savefig(path, dpi=150, bbox_inches='tight', facecolor='#0f1117')
    plt.close()
    print(f'  wrote {name}')

# ── Data ────────────────────────────────────────────────────────────────────

sizes_label = ['1 KB', '64 KB', '1 MB', '16 MB', '64 MB']
sizes_bytes = [1024, 65536, 1048576, 16777216, 67108864]

cpu_ecb  = {'PRESENT-80': 2.43,  'SPECK-64/128': 262.6, 'AES-128': 11.14}
cpu_ctr  = {'PRESENT-80': 0.72,  'SPECK-64/128': 220.5, 'AES-128': 10.91}
cpu_cbc  = {'PRESENT-80': 0.69,  'SPECK-64/128': 152.6, 'AES-128': 11.02}
cpb      = {'PRESENT-80': 1492,  'SPECK-64/128': 13.81, 'AES-128': 325.3}
ks_cyc   = {'PRESENT-80': 21247, 'SPECK-64/128': 184,   'AES-128': 665}
sb_cyc   = {'PRESENT-80': 36632, 'SPECK-64/128': 114,   'AES-128': 4408}
gate_eq  = {'PRESENT-80': 1570,  'SPECK-64/128': 1280,  'AES-128': 3400}

cpu_sweep = {
    'PRESENT-80':   [2.22, 2.21, 2.18, 2.20, 2.24],
    'SPECK-64/128': [250.8, 227.9, 241.8, 242.9, 197.8],
    'AES-128':      [11.31, 11.01, 10.94, 10.69, 10.81],
}

gpu_enc = {
    'PRESENT-80':   [0.0148, 1.301, 1.693, 1.794, 1.857],
    'SPECK-64/128': [0.0165, 3.050, 42.31, 106.3, 104.3],
}
gpu_dec = {
    'PRESENT-80':   [0.0152, 1.308, 1.699, 1.800, 1.862],
    'SPECK-64/128': [0.0162, 3.068, 43.15, 107.1, 106.4],
}

ciphers3 = ['PRESENT-80', 'SPECK-64/128', 'AES-128']
ciphers2 = ['PRESENT-80', 'SPECK-64/128']

# ── Figure 1: CPU ECB throughput — horizontal log bar ───────────────────────
fig, ax = plt.subplots(figsize=(10, 4), facecolor='#0f1117')
ax.set_facecolor('#0f1117')
vals = [cpu_ecb[c] for c in ciphers3]
bars = ax.barh(ciphers3, vals, color=[C[c] for c in ciphers3], height=0.5)
ax.set_xscale('log')
ax.set_xlabel('Throughput (MB/s)  —  log scale', color=ACCENT)
ax.set_title('CPU ECB Throughput  |  AMD Ryzen 7 8845HS  |  g++ -O3', color=ACCENT, pad=10)
ax.tick_params(colors=ACCENT)
ax.spines['bottom'].set_color(GRID)
ax.spines['top'].set_visible(False)
ax.spines['right'].set_visible(False)
ax.spines['left'].set_color(GRID)
ax.grid(axis='x', color=GRID, linewidth=0.5)
for bar, v, c in zip(bars, vals, ciphers3):
    ax.text(v * 1.1, bar.get_y() + bar.get_height()/2,
            f'{v:.1f} MB/s', va='center', color=C[c], fontsize=11, fontweight='bold')
# annotate gap
ax.annotate('', xy=(262.6, 0), xytext=(2.43, 0),
            arrowprops=dict(arrowstyle='<->', color='#ff0000', lw=1.5),
            xycoords=('data','axes fraction'), textcoords=('data','axes fraction'))
ax.text(25, 0.08, '~108×', color='#ff0000', fontsize=12, fontweight='bold',
        transform=ax.transAxes if False else ax.transData, va='bottom', ha='center')
plt.tight_layout()
savefig('fig1_cpu_ecb_log.png')

# ── Figure 2: CPU modes — grouped bar (log scale) ───────────────────────────
fig, ax = plt.subplots(figsize=(11, 5), facecolor='#0f1117')
ax.set_facecolor('#0f1117')
modes = ['ECB', 'CTR', 'CBC']
data = {
    'PRESENT-80':   [2.43, 0.72, 0.69],
    'SPECK-64/128': [262.6, 220.5, 152.6],
    'AES-128':      [11.14, 10.91, 11.02],
}
x = np.arange(len(modes))
w = 0.25
for i, cipher in enumerate(ciphers3):
    bars = ax.bar(x + (i - 1)*w, data[cipher], w, label=cipher,
                  color=C[cipher], alpha=0.9)
ax.set_yscale('log')
ax.set_xticks(x)
ax.set_xticklabels(modes, color=ACCENT, fontsize=12)
ax.set_ylabel('Throughput (MB/s)  —  log scale', color=ACCENT)
ax.set_title('CPU Throughput by Mode  |  ECB / CTR / CBC', color=ACCENT, pad=10)
ax.tick_params(colors=ACCENT)
ax.spines['bottom'].set_color(GRID)
ax.spines['top'].set_visible(False)
ax.spines['right'].set_visible(False)
ax.spines['left'].set_color(GRID)
ax.grid(axis='y', color=GRID, linewidth=0.5)
ax.legend(facecolor='#1a1a2e', edgecolor=GRID, labelcolor=ACCENT)
plt.tight_layout()
savefig('fig2_cpu_modes_log.png')

# ── Figure 3: CPU sweep — line chart (log x-axis) ───────────────────────────
fig, ax = plt.subplots(figsize=(10, 5), facecolor='#0f1117')
ax.set_facecolor('#0f1117')
for cipher in ciphers3:
    ax.plot(sizes_bytes, cpu_sweep[cipher], '-o', color=C[cipher], label=cipher,
            linewidth=2, markersize=7)
ax.set_xscale('log')
ax.set_yscale('log')
ax.set_xticks(sizes_bytes)
ax.set_xticklabels(sizes_label, color=ACCENT)
ax.set_xlabel('Input size', color=ACCENT)
ax.set_ylabel('Throughput (MB/s)  —  log scale', color=ACCENT)
ax.set_title('CPU Throughput vs Input Size  (ECB, single core)', color=ACCENT, pad=10)
ax.tick_params(colors=ACCENT)
ax.spines['bottom'].set_color(GRID)
ax.spines['top'].set_visible(False)
ax.spines['right'].set_visible(False)
ax.spines['left'].set_color(GRID)
ax.grid(color=GRID, linewidth=0.5)
ax.legend(facecolor='#1a1a2e', edgecolor=GRID, labelcolor=ACCENT)
for cipher in ciphers3:
    y = cpu_sweep[cipher][-1]
    ax.annotate(f'{y:.1f}', xy=(sizes_bytes[-1], y), xytext=(6, 0),
                textcoords='offset points', color=C[cipher], fontsize=9, va='center')
plt.tight_layout()
savefig('fig3_cpu_sweep.png')

# ── Figure 4: GPU sweep — log-log line chart (THE STAR CHART) ───────────────
fig, ax = plt.subplots(figsize=(11, 6), facecolor='#0f1117')
ax.set_facecolor('#0f1117')
for cipher in ciphers2:
    ax.plot(sizes_bytes, gpu_enc[cipher], '-o', color=C[cipher], label=f'{cipher} (enc)',
            linewidth=2.5, markersize=8)
ax.set_xscale('log')
ax.set_yscale('log')
ax.set_xticks(sizes_bytes)
ax.set_xticklabels(sizes_label, color=ACCENT, fontsize=11)
ax.set_xlabel('Batch size', color=ACCENT, fontsize=12)
ax.set_ylabel('Throughput (GB/s)  —  log scale', color=ACCENT, fontsize=12)
ax.set_title('GPU Throughput vs Batch Size  |  RTX 4070 Laptop (sm_89)  |  5 trials/size',
             color=ACCENT, pad=12)
ax.tick_params(colors=ACCENT)
ax.spines['bottom'].set_color(GRID)
ax.spines['top'].set_visible(False)
ax.spines['right'].set_visible(False)
ax.spines['left'].set_color(GRID)
ax.grid(color=GRID, linewidth=0.5)
ax.legend(facecolor='#1a1a2e', edgecolor=GRID, labelcolor=ACCENT, fontsize=11)

# Annotations
ax.annotate('Kernel launch\njitter dominates', xy=(1024, 0.015),
            xytext=(8000, 0.002), color='#aaaaaa', fontsize=9,
            arrowprops=dict(arrowstyle='->', color='#aaaaaa', lw=1))
ax.annotate('SPECK: 6,000×\nscaling 1KB→64MB', xy=(67108864, 104.3),
            xytext=(2000000, 60), color=C['SPECK-64/128'], fontsize=10,
            arrowprops=dict(arrowstyle='->', color=C['SPECK-64/128'], lw=1.2))
ax.annotate('PRESENT: saturates\nat ~1.86 GB/s\n(compute-bound)', xy=(67108864, 1.857),
            xytext=(2000000, 0.3), color=C['PRESENT-80'], fontsize=10,
            arrowprops=dict(arrowstyle='->', color=C['PRESENT-80'], lw=1.2))
# Mark peak values
ax.axhline(104.3, color=C['SPECK-64/128'], linewidth=0.8, linestyle='--', alpha=0.4)
ax.axhline(1.857, color=C['PRESENT-80'],   linewidth=0.8, linestyle='--', alpha=0.4)
ax.text(1024*1.5, 104.3 * 1.15, '104.3 GB/s', color=C['SPECK-64/128'],
        fontsize=10, fontweight='bold', va='bottom')
ax.text(1024*1.5, 1.857 * 1.2, '1.857 GB/s', color=C['PRESENT-80'],
        fontsize=10, fontweight='bold', va='bottom')
plt.tight_layout()
savefig('fig4_gpu_sweep_loglog.png')

# ── Figure 5: GPU peak throughput — grouped bar (enc + dec) ─────────────────
fig, ax = plt.subplots(figsize=(9, 5), facecolor='#0f1117')
ax.set_facecolor('#0f1117')
ciphers2_labels = ['PRESENT-80', 'SPECK-64/128']
enc_vals = [1.857, 104.3]
dec_vals = [1.862, 106.4]
x = np.arange(len(ciphers2_labels))
w = 0.35
b1 = ax.bar(x - w/2, enc_vals, w, label='Encrypt', color=[C[c] for c in ciphers2_labels], alpha=0.95)
b2 = ax.bar(x + w/2, dec_vals, w, label='Decrypt', color=[C[c] for c in ciphers2_labels], alpha=0.6)
ax.set_yscale('log')
ax.set_xticks(x)
ax.set_xticklabels(ciphers2_labels, color=ACCENT, fontsize=12)
ax.set_ylabel('Throughput (GB/s)  —  log scale', color=ACCENT)
ax.set_title('GPU Peak Throughput  |  64 MB batch  |  RTX 4070 Laptop', color=ACCENT, pad=10)
ax.tick_params(colors=ACCENT)
ax.spines['bottom'].set_color(GRID)
ax.spines['top'].set_visible(False)
ax.spines['right'].set_visible(False)
ax.spines['left'].set_color(GRID)
ax.grid(axis='y', color=GRID, linewidth=0.5)
# Speedup annotations
ax.text(0, enc_vals[0]*1.5, '~829× vs CPU', ha='center', color=C['PRESENT-80'],
        fontsize=10, fontweight='bold')
ax.text(1, enc_vals[1]*1.3, '~527× vs CPU', ha='center', color=C['SPECK-64/128'],
        fontsize=10, fontweight='bold')
# Value labels
for bar, v in zip(b1, enc_vals):
    ax.text(bar.get_x() + bar.get_width()/2, v*0.6,
            f'{v:.3f}' if v < 2 else f'{v:.1f}', ha='center', va='top',
            color='white', fontsize=9, fontweight='bold')
handles = [mpatches.Patch(color='white', alpha=0.95, label='Encrypt'),
           mpatches.Patch(color='white', alpha=0.6,  label='Decrypt')]
ax.legend(handles=handles, facecolor='#1a1a2e', edgecolor=GRID, labelcolor=ACCENT)
plt.tight_layout()
savefig('fig5_gpu_peak_bar.png')

# ── Figure 6: Cycles per byte — horizontal log bar ──────────────────────────
fig, ax = plt.subplots(figsize=(10, 4), facecolor='#0f1117')
ax.set_facecolor('#0f1117')
cpb_vals = [cpb[c] for c in ciphers3]
bars = ax.barh(ciphers3, cpb_vals, color=[C[c] for c in ciphers3], height=0.5)
ax.set_xscale('log')
ax.set_xlabel('Cycles per byte  —  log scale', color=ACCENT)
ax.set_title('CPU Cycles per Byte  |  AMD Ryzen 7 8845HS  |  g++ -O3', color=ACCENT, pad=10)
ax.tick_params(colors=ACCENT)
ax.spines['bottom'].set_color(GRID)
ax.spines['top'].set_visible(False)
ax.spines['right'].set_visible(False)
ax.spines['left'].set_color(GRID)
ax.grid(axis='x', color=GRID, linewidth=0.5)
for bar, v, c in zip(bars, cpb_vals, ciphers3):
    ax.text(v * 1.15, bar.get_y() + bar.get_height()/2,
            f'{v:.2f} cyc/B' if v < 100 else f'{v:,.0f} cyc/B',
            va='center', color=C[c], fontsize=11, fontweight='bold')
plt.tight_layout()
savefig('fig6_cycles_per_byte.png')

# ── Figure 7: Key schedule cycles — bar ─────────────────────────────────────
fig, ax = plt.subplots(figsize=(9, 4), facecolor='#0f1117')
ax.set_facecolor('#0f1117')
ks_vals = [ks_cyc[c] for c in ciphers3]
bars = ax.bar(ciphers3, ks_vals, color=[C[c] for c in ciphers3], width=0.5)
ax.set_yscale('log')
ax.set_ylabel('Cycles per key expansion  —  log scale', color=ACCENT)
ax.set_title('Key Schedule Cost  |  CPU (mean of 10×10k expansions)', color=ACCENT, pad=10)
ax.tick_params(colors=ACCENT)
ax.spines['bottom'].set_color(GRID)
ax.spines['top'].set_visible(False)
ax.spines['right'].set_visible(False)
ax.spines['left'].set_color(GRID)
ax.grid(axis='y', color=GRID, linewidth=0.5)
for bar, v, c in zip(bars, ks_vals, ciphers3):
    ax.text(bar.get_x() + bar.get_width()/2, v * 1.3,
            f'{v:,} cyc', ha='center', color=C[c], fontsize=11, fontweight='bold')
# re-keying callout
ax.annotate('3.6× faster\nre-keying than AES', xy=(1, 184), xytext=(1, 3000),
            ha='center', color=C['SPECK-64/128'], fontsize=9,
            arrowprops=dict(arrowstyle='->', color=C['SPECK-64/128']))
plt.tight_layout()
savefig('fig7_ks_cycles.png')

# ── Figure 8: Single-block latency — bar ────────────────────────────────────
fig, ax = plt.subplots(figsize=(9, 4), facecolor='#0f1117')
ax.set_facecolor('#0f1117')
sb_vals = [sb_cyc[c] for c in ciphers3]
bars = ax.bar(ciphers3, sb_vals, color=[C[c] for c in ciphers3], width=0.5)
ax.set_yscale('log')
ax.set_ylabel('Cycles per single block  —  log scale', color=ACCENT)
ax.set_title('Single-Block Latency  |  median of 1M RDTSC calls  |  compiler elision fixed',
             color=ACCENT, pad=10)
ax.tick_params(colors=ACCENT)
ax.spines['bottom'].set_color(GRID)
ax.spines['top'].set_visible(False)
ax.spines['right'].set_visible(False)
ax.spines['left'].set_color(GRID)
ax.grid(axis='y', color=GRID, linewidth=0.5)
mhz = 3792.93
for bar, v, c in zip(bars, sb_vals, ciphers3):
    us = v / mhz
    ax.text(bar.get_x() + bar.get_width()/2, v * 1.4,
            f'{v:,} cyc\n({us:.2f} µs)', ha='center', color=C[c], fontsize=10, fontweight='bold')
plt.tight_layout()
savefig('fig8_single_block_latency.png')

# ── Figure 9: Gate equivalents — bar ────────────────────────────────────────
fig, ax = plt.subplots(figsize=(9, 4), facecolor='#0f1117')
ax.set_facecolor('#0f1117')
ge_vals = [gate_eq[c] for c in ciphers3]
bars = ax.bar(ciphers3, ge_vals, color=[C[c] for c in ciphers3], width=0.5)
ax.axhline(2000, color='#ff4444', linewidth=1.5, linestyle='--', label='2,000 GE IoT budget')
ax.set_ylabel('Gate Equivalents (GE)', color=ACCENT)
ax.set_title('Hardware Area  |  Published Gate-Equivalent Counts', color=ACCENT, pad=10)
ax.tick_params(colors=ACCENT)
ax.spines['bottom'].set_color(GRID)
ax.spines['top'].set_visible(False)
ax.spines['right'].set_visible(False)
ax.spines['left'].set_color(GRID)
ax.grid(axis='y', color=GRID, linewidth=0.5)
for bar, v, c in zip(bars, ge_vals, ciphers3):
    ax.text(bar.get_x() + bar.get_width()/2, v + 60,
            f'{v:,} GE', ha='center', color=C[c], fontsize=11, fontweight='bold')
ax.text(2.6, 2100, '2,000 GE budget', color='#ff4444', fontsize=9)
ax.legend(facecolor='#1a1a2e', edgecolor=GRID, labelcolor=ACCENT)
plt.tight_layout()
savefig('fig9_gate_equivalents.png')

# ── Figure 10: Security radar chart ─────────────────────────────────────────
categories = ['SW Throughput', 'Key Security\n(key length)', 'Block Security\n(block size)',
              'HW Efficiency\n(lower GE = better)', 'Cryptanalysis\nMaturity']
N = len(categories)
scores = {
    'PRESENT-80':   [1, 3, 3, 4, 4],
    'SPECK-64/128': [5, 5, 3, 5, 2],
    'AES-128':      [2, 5, 5, 1, 5],
}
angles = [n / float(N) * 2 * np.pi for n in range(N)]
angles += angles[:1]

fig, ax = plt.subplots(figsize=(8, 8), subplot_kw=dict(polar=True), facecolor='#0f1117')
ax.set_facecolor('#0f1117')
ax.spines['polar'].set_color(GRID)
ax.grid(color=GRID, linewidth=0.5)
plt.xticks(angles[:-1], categories, color=ACCENT, size=11)
ax.set_rlabel_position(30)
ax.set_yticks([1, 2, 3, 4, 5])
ax.set_yticklabels(['1', '2', '3', '4', '5'], color='#888888', size=8)
ax.set_ylim(0, 5)

for cipher, vals in scores.items():
    vals_plot = vals + vals[:1]
    ax.plot(angles, vals_plot, '-o', color=C[cipher], linewidth=2, markersize=6, label=cipher)
    ax.fill(angles, vals_plot, alpha=0.1, color=C[cipher])

ax.set_title('Security & Performance Trade-offs\n(5 = best on each axis)', color=ACCENT,
             pad=25, fontsize=13)
ax.legend(loc='upper right', bbox_to_anchor=(1.35, 1.15),
          facecolor='#1a1a2e', edgecolor=GRID, labelcolor=ACCENT, fontsize=11)
plt.tight_layout()
savefig('fig10_security_radar.png')

# ── Figure 11: Combined CPU bar (ECB only) with INVERSION callout ────────────
fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(13, 5), facecolor='#0f1117')
for ax in (ax1, ax2):
    ax.set_facecolor('#0f1117')

# Left: CPU ECB (log)
vals = [cpu_ecb[c] for c in ciphers3]
bars = ax1.barh(ciphers3, vals, color=[C[c] for c in ciphers3], height=0.5)
ax1.set_xscale('log')
ax1.set_xlabel('CPU ECB (MB/s, log scale)', color=ACCENT)
ax1.set_title('Software Performance', color=ACCENT)
ax1.tick_params(colors=ACCENT)
for sp in ['top', 'right']:
    ax1.spines[sp].set_visible(False)
ax1.spines['left'].set_color(GRID)
ax1.spines['bottom'].set_color(GRID)
ax1.grid(axis='x', color=GRID, linewidth=0.5)
for bar, v, c in zip(bars, vals, ciphers3):
    ax1.text(v*1.1, bar.get_y()+bar.get_height()/2, f'{v:.1f}',
             va='center', color=C[c], fontsize=10, fontweight='bold')

# Right: Gate equivalents (linear)
ge_vals = [gate_eq[c] for c in ciphers3]
bars2 = ax2.barh(ciphers3, ge_vals, color=[C[c] for c in ciphers3], height=0.5)
ax2.axvline(2000, color='#ff4444', linewidth=1.5, linestyle='--')
ax2.set_xlabel('Gate Equivalents (smaller = better HW)', color=ACCENT)
ax2.set_title('Hardware Area', color=ACCENT)
ax2.tick_params(colors=ACCENT)
for sp in ['top', 'right']:
    ax2.spines[sp].set_visible(False)
ax2.spines['left'].set_color(GRID)
ax2.spines['bottom'].set_color(GRID)
ax2.grid(axis='x', color=GRID, linewidth=0.5)
for bar, v, c in zip(bars2, ge_vals, ciphers3):
    ax2.text(v+40, bar.get_y()+bar.get_height()/2, f'{v:,}',
             va='center', color=C[c], fontsize=10, fontweight='bold')

fig.suptitle('The Inversion: PRESENT loses in software, wins in silicon',
             color='#ff4444', fontsize=13, fontweight='bold', y=1.02)
plt.tight_layout()
savefig('fig11_sw_vs_hw_inversion.png')

print('\nAll figures generated successfully.')
