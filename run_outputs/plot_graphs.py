import os
import matplotlib.pyplot as plt

# 1. Define the Dataset
sizes = ['1 KB', '64 KB', '1 MB', '16 MB', '64 MB']

data = {
    'PRESENT-80': {
        'CPU_Enc': [1.4747, 1.4482, 1.4528, 1.4161, 1.4267],
        'CPU_Dec': [1.4660, 1.4303, 1.4352, 1.3961, 1.4159],
        'GPU_ECB_Enc': [43.9047, 1555.9050, 6434.4340, 6680.7850, 7520.9550],
        'GPU_ECB_Dec': [43.7095, 1579.9500, 6520.9950, 6721.9170, 7510.5850],
        'GPU_CTR_Enc': [43.7316, 1562.469, 6554.6489, 7456.3601, 7540.5214],
        'GPU_CTR_Dec': [43.7488, 1562.376, 6540.519, 7457.5905, 7504.6233]
    },
    'SPECK-64': {
        'CPU_Enc': [1178.5260, 1211.7540, 1112.0160, 1081.1890, 1111.0090],
        'CPU_Dec': [890.0602, 912.0065, 858.7911, 831.6268, 860.9152],
        'GPU_ECB_Enc': [571.4286, 34320.95, 225986.2, 830621.0, 356004.6],
        'GPU_ECB_Dec': [549.9038, 34042.55, 235402.3, 1096378.0, 483326.1],
        'GPU_CTR_Enc': [603.25, 35210.7841, 221106.6095, 815631.6125, 358966.1363],
        'GPU_CTR_Dec': [599.5204, 36734.1088, 246375.94, 1065193.025, 479875.5225]
    },
    'AES-128': {
        'CPU_Enc': [23.9206, 23.7059, 23.3759, 23.6137, 23.6295],
        'CPU_Dec': [15.0428, 14.9077, 14.9817, 14.8847, 14.9041],
        'GPU_ECB_Enc': [88.5147, 3257.495, 26222.79, 32483.77, 32664.19],
        'GPU_ECB_Dec': [90.9959, 3476.324, 27997.26, 35223.52, 35432.29],
        'GPU_CTR_Enc': [99.7276, 2191.6119, 17605.8455, 20554.8324, 20630.2546],
        'GPU_CTR_Dec': [98.6601, 2190.2807, 17655.172, 20576.4519, 20638.7819]
    }
}

# 2. Plot Generation Loop
for cipher_name, metrics in data.items():
    # Setup a 3-panel figure layout
    fig, axes = plt.subplots(1, 3, figsize=(18, 5.5))
    fig.suptitle(f'{cipher_name} Performance Analysis', fontsize=16, fontweight='bold', y=0.98)
    
    # --- Panel 1: CPU Throughput (Linear Scale) ---
    ax_cpu = axes[0]
    ax_cpu.plot(sizes, metrics['CPU_Enc'], label='CPU Enc', color='#1f77b4', marker='o', linestyle='-', linewidth=2)
    ax_cpu.plot(sizes, metrics['CPU_Dec'], label='CPU Dec', color='#ff7f0e', marker='s', linestyle='--', linewidth=2)
    
    ax_cpu.set_title('1. CPU Throughput', fontsize=12, fontweight='bold')
    ax_cpu.set_ylabel('Throughput (MB/s)', fontsize=11)
    # Start y-axis at 0 for clearer visual baseline on CPU bounds
    ax_cpu.set_ylim(bottom=0, top=max(max(metrics['CPU_Enc']), max(metrics['CPU_Dec'])) * 1.2)
    ax_cpu.grid(True, linestyle='--', alpha=0.6)
    ax_cpu.legend(loc='best')
    
    # --- Panel 2: GPU Throughput (Log Scale) ---
    ax_gpu = axes[1]
    ax_gpu.plot(sizes, metrics['GPU_ECB_Enc'], label='GPU ECB Enc', color='#2ca02c', marker='o', linestyle='-')
    ax_gpu.plot(sizes, metrics['GPU_ECB_Dec'], label='GPU ECB Dec', color='#d62728', marker='s', linestyle='--')
    ax_gpu.plot(sizes, metrics['GPU_CTR_Enc'], label='GPU CTR Enc', color='#9467bd', marker='D', linestyle='-')
    ax_gpu.plot(sizes, metrics['GPU_CTR_Dec'], label='GPU CTR Dec', color='#8c564b', marker='^', linestyle='--')
    
    ax_gpu.set_title('2. GPU Throughput (ECB vs CTR)', fontsize=12, fontweight='bold')
    ax_gpu.set_ylabel('Throughput (MB/s) - Log Scale', fontsize=11)
    ax_gpu.set_yscale('log')
    ax_gpu.grid(True, which='both', linestyle='--', alpha=0.6)
    ax_gpu.legend(loc='lower right')
    
    # --- Panel 3: Speedup Multipliers (Log Scale) ---
    ax_speed = axes[2]
    
    # Calculate multipliers relative to respective CPU base
    speedup_ecb_enc = [g / c for g, c in zip(metrics['GPU_ECB_Enc'], metrics['CPU_Enc'])]
    speedup_ecb_dec = [g / c for g, c in zip(metrics['GPU_ECB_Dec'], metrics['CPU_Dec'])]
    speedup_ctr_enc = [g / c for g, c in zip(metrics['GPU_CTR_Enc'], metrics['CPU_Enc'])]
    speedup_ctr_dec = [g / c for g, c in zip(metrics['GPU_CTR_Dec'], metrics['CPU_Dec'])]
    
    ax_speed.plot(sizes, speedup_ecb_enc, label='ECB Enc Speedup', color='#2ca02c', marker='o', linestyle='-')
    ax_speed.plot(sizes, speedup_ecb_dec, label='ECB Dec Speedup', color='#d62728', marker='s', linestyle='--')
    ax_speed.plot(sizes, speedup_ctr_enc, label='CTR Enc Speedup', color='#9467bd', marker='D', linestyle='-')
    ax_speed.plot(sizes, speedup_ctr_dec, label='CTR Dec Speedup', color='#8c564b', marker='^', linestyle='--')
    
    ax_speed.set_title('3. Speedup Multiplier (vs CPU)', fontsize=12, fontweight='bold')
    ax_speed.set_ylabel('Execution Multiplier (x) - Log Scale', fontsize=11)
    ax_speed.set_yscale('log')
    ax_speed.grid(True, which='both', linestyle='--', alpha=0.6)
    ax_speed.legend(loc='lower right')

    # Global X-Axis formatting across all panels
    for ax in axes:
        ax.set_xlabel('Plaintext Allocation Size', fontsize=10)
        ax.tick_params(axis='both', which='major', labelsize=9)

    plt.tight_layout()
    
    # Save output plots locally
    filename = f"{cipher_name.lower().replace('-', '')}_performance_graphs.png"
    plt.savefig(filename, dpi=300, bbox_inches='tight')
    print(f"[SUCCESS] Figure exported -> {filename}")
    plt.close()
