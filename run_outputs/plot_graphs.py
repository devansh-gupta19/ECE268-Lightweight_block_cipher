import matplotlib.pyplot as plt

# 1. Define the Dataset
sizes = ['1 KB', '64 KB', '1 MB', '16 MB', '64 MB']

data = {
    'PRESENT-80': {
        'CPU_Enc': [1.4747, 1.4482, 1.4528, 1.4161, 1.4267],
        'CPU_Dec': [1.4660, 1.4303, 1.4352, 1.3961, 1.4159],
        'GPU_Enc': [43.9047, 1555.905, 6434.434, 6680.785, 7520.955],
        'GPU_Dec': [43.7095, 1579.950, 6520.995, 6721.917, 7510.585]
    },
    'SPECK-64': {
        'CPU_Enc': [1178.526, 1211.754, 1112.016, 1081.189, 1111.009],
        'CPU_Dec': [890.0602, 912.0065, 858.7911, 858.1835, 861.6119],
        'GPU_Enc': [571.4286, 34320.95, 225986.2, 830621.0, 356004.6],
        'GPU_Dec': [549.9038, 34042.55, 235402.3, 1096378.0, 483326.1]
    },
    'AES-128': {
        'CPU_Enc': [23.9206, 23.7059, 23.3759, 23.6137, 23.6295],
        'CPU_Dec': [15.0428, 14.9077, 14.9817, 14.8847, 14.9041],
        'GPU_Enc': [88.5147, 3257.495, 26222.79, 32483.77, 32664.19],
        'GPU_Dec': [90.9959, 3476.324, 27997.26, 35223.52, 35432.29]
    }
}

# 2. Generate a separate 3-panel figure for each cipher
for cipher_name, metrics in data.items():
    # Create a 1x3 grid for the current cipher
    fig, axes = plt.subplots(1, 3, figsize=(18, 5))
    fig.suptitle(f'{cipher_name} Performance Breakdown', fontsize=16, fontweight='bold', y=1.05)
    
    # --- Panel 1: CPU Throughput ---
    ax_cpu = axes[0]
    ax_cpu.plot(sizes, metrics['CPU_Enc'], label='CPU Enc', color='#1f77b4', marker='o', linestyle='-', linewidth=2)
    ax_cpu.plot(sizes, metrics['CPU_Dec'], label='CPU Dec', color='#ff7f0e', marker='s', linestyle='--', linewidth=2)
    ax_cpu.set_title(f'{cipher_name} CPU Throughput', fontsize=14)
    ax_cpu.set_ylabel('Throughput (MB/s)', fontsize=12)
    ax_cpu.set_xlabel('Plaintext Size', fontsize=12)
    
    # NEW: Force the Y-axis to start at 0 to accurately portray the gap
    max_cpu = max(max(metrics['CPU_Enc']), max(metrics['CPU_Dec']))
    ax_cpu.set_ylim(0, max_cpu * 1.2) # Adds 20% visual headroom above the highest point
    
    ax_cpu.grid(True, linestyle='--', alpha=0.6)
    ax_cpu.legend(loc='best')
    
    # --- Panel 2: GPU Throughput ---
    ax_gpu = axes[1]
    ax_gpu.plot(sizes, metrics['GPU_Enc'], label='GPU Enc', color='#2ca02c', marker='o', linestyle='-', linewidth=2)
    ax_gpu.plot(sizes, metrics['GPU_Dec'], label='GPU Dec', color='#d62728', marker='s', linestyle='--', linewidth=2)
    ax_gpu.set_title(f'{cipher_name} GPU Throughput', fontsize=14)
    ax_gpu.set_ylabel('Throughput (MB/s) - Log Scale', fontsize=12)
    ax_gpu.set_xlabel('Plaintext Size', fontsize=12)
    ax_gpu.set_yscale('log') # Crucial for showing the saturation curve
    ax_gpu.grid(True, which='both', linestyle='--', alpha=0.6)
    ax_gpu.legend(loc='best')
    
    # --- Panel 3: Speedup Multiplier ---
    ax_speed = axes[2]
    # Calculate speedup (GPU / CPU) for each size
    speedup_enc = [g / c for g, c in zip(metrics['GPU_Enc'], metrics['CPU_Enc'])]
    speedup_dec = [g / c for g, c in zip(metrics['GPU_Dec'], metrics['CPU_Dec'])]
    
    ax_speed.plot(sizes, speedup_enc, label='Speedup Enc', color='#9467bd', marker='o', linestyle='-', linewidth=2)
    ax_speed.plot(sizes, speedup_dec, label='Speedup Dec', color='#8c564b', marker='s', linestyle='--', linewidth=2)
    ax_speed.set_title(f'{cipher_name} Speedup Multiplier', fontsize=14)
    ax_speed.set_ylabel('Speedup (x) - Log Scale', fontsize=12)
    ax_speed.set_xlabel('Plaintext Size', fontsize=12)
    ax_speed.set_yscale('log') # Crucial for SPECK's massive multipliers
    ax_speed.grid(True, which='both', linestyle='--', alpha=0.6)
    ax_speed.legend(loc='best')
    
    # Adjust layout to prevent overlap
    plt.tight_layout()
    
    # Optional: Save each graph automatically based on its cipher name
    plt.savefig(f'{cipher_name}_performance.png', dpi=300, bbox_inches='tight')

# Render all 3 figures
plt.show()