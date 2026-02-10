# -*- coding: utf-8 -*-
"""
Created on Wed Jan 14 14:57:02 2026

@author: monji
"""
import os
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.path import Path
from matplotlib.patches import PathPatch
import pandas as pd
from PIL import Image
import math
import cairosvg

# dir where this script is located
script_dir = os.path.dirname(os.path.abspath(__file__))

results_dir = os.path.join(script_dir, 'results')
os.makedirs(results_dir, exist_ok=True)
excel_path = os.path.join(script_dir, 'icons.xlsx') # icons descriptions
df = pd.read_excel(excel_path)

#%%
def create_star(num_points, inner_radius=0.1, outer_radius=0.25):
    verts = []
    codes = [Path.MOVETO]
    angle = 2 * np.pi / (num_points * 2)

    for i in range(num_points * 2):
        r = outer_radius if i % 2 == 0 else inner_radius
        x = 0.5 + r * np.cos(i * angle - np.pi / 2)
        y = 0.5 + r * np.sin(i * angle - np.pi / 2)
        verts.append((x, y))
        codes.append(Path.LINETO)

    verts.append(verts[0])  # clse path
    codes[-1] = Path.CLOSEPOLY
    return PathPatch(Path(verts, codes), facecolor=None, edgecolor='black', linewidth=1)


#%%

figsize = (1, 1) 
# figsize = (0.12, 0.12)  # In inches
# dpi = 100  # 0.12 in * 100 dpi = 12px
marker_size = 1000

# Custom shape-based marker sizes
shape_scaling = {
    'D': 600,
    '^': 900,
    'v': 900,
    's': 850,
    'o': 900,
    'H': 950,
    'pointed_circle': 1.0,  # scale outer/inner manually
    'star5': (0.12, 0.28),
    'star6': (0.14, 0.3),
    'star4': (0.15, 0.32),
    'trapezium': 1.0,
    'rectangle': 1.0,
    'half_square_t': 1.0,
    'half_square_b': 1.0
}


for _, row in df.iterrows():
    node_type = row['node_type']
    color = row['color']
    shape = row['shape_code']
    label = row.get('label', '')

    fig, ax = plt.subplots(figsize=figsize)

    if shape == 'rectangle':
        # custom rectangle 
        rect = mpatches.Rectangle(
        (0.5 - 0.2, 0.5 - 0.1),
        0.4, 0.2,
        facecolor=color,
        edgecolor='black'
        )
        ax.add_patch(rect)
        
    elif shape == 'trapezium':
        top_width = 0.6
        bottom_width = 0.3
        height = 0.5
    
        top_y = 0.5 + height / 2
        bottom_y = 0.5 - height / 2
    
        verts = [
            (0.5 - top_width / 2, top_y),     # top-left
            (0.5 + top_width / 2, top_y),     # top-right
            (0.5 + bottom_width / 2, bottom_y),  # bottom-right
            (0.5 - bottom_width / 2, bottom_y),  # bottom-left
        ]
    
        trapezium = mpatches.Polygon(verts, closed=True,
                                     facecolor=color,
                                     edgecolor='black',
                                     linewidth=1)
        ax.add_patch(trapezium)
        
    elif shape == 'pointed_circle':
        # outlet shuld have outer circle + inner dot
        outer = mpatches.Circle((0.5, 0.5), 0.25,
                                facecolor='none',
                                edgecolor='black',
                                linewidth=2)
        inner = mpatches.Circle((0.5, 0.5), 0.1,
                                facecolor=color,
                                edgecolor='none')
        ax.add_patch(outer)
        ax.add_patch(inner)
        
    elif shape == 'star5':
        star = create_star(num_points=5, inner_radius=0.12, outer_radius=0.25)
        star.set_facecolor(color)
        ax.add_patch(star)

    elif shape == 'star6':
        star = create_star(num_points=6, inner_radius=0.12, outer_radius=0.25)
        star.set_facecolor(color)
        ax.add_patch(star)

    elif shape == 'star4':
        star = create_star(num_points=4, inner_radius=0.14, outer_radius=0.25)
        star.set_facecolor(color)
        ax.add_patch(star)
        
    elif shape == 'half_square_t':
        # outer square border
        square = mpatches.Rectangle(
            (0.5 - 0.25, 0.5 - 0.25), 0.5, 0.5,
            facecolor='white',
            edgecolor='black',
            linewidth=1
        )
        # top half filled
        fill = mpatches.Rectangle(
            (0.5 - 0.25, 0.5), 0.5, 0.25,
            facecolor=color,
            edgecolor='black'
        )
        ax.add_patch(square)
        ax.add_patch(fill)

    elif shape == 'half_square_b':
        # outer squre border
        square = mpatches.Rectangle(
            (0.5 - 0.25, 0.5 - 0.25), 0.5, 0.5,
            facecolor='white',
            edgecolor='black',
            linewidth=1
        )
        # bottom half filled
        fill = mpatches.Rectangle(
            (0.5 - 0.25, 0.5 - 0.25), 0.5, 0.25,
            facecolor=color,
            edgecolor='black'
        )
        ax.add_patch(square)
        ax.add_patch(fill)
        

    else:
        # normal scatter marker
        safe_edgecolor_shapes = {'^', 'v', 's', 'D', 'o', 'H'}
        use_edge = shape in safe_edgecolor_shapes
        this_size = shape_scaling.get(shape, marker_size)

        current_marker_size = 500 if node_type == "junction" else this_size
        ax.scatter(0.5, 0.5, marker=shape, color=color,
           s=current_marker_size,
           edgecolors='black' if use_edge else None)


    # # labeling
    # if pd.notna(label) and label.strip():
    #     ax.text(0.5, 0.5, label.strip(), ha='center', va='center',
    #             fontsize=20, fontweight='bold', color='black')

    
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.axis('off')

    # save svg
    filename = os.path.join(results_dir, f"{node_type}.svg")
    plt.savefig(filename, format='svg', bbox_inches='tight', transparent=True)
    
    
    # PNG needed for overview
    png_filename = os.path.join(results_dir, f"{node_type}.png")
    plt.savefig(png_filename, format='png', dpi=300, bbox_inches='tight', transparent=True)
    # plt.savefig(png_filename, format='png', dpi=dpi,
            # bbox_inches='tight', pad_inches=0, transparent=True)
    plt.show()
    plt.close(fig)

print("saved to 'results' folder")


#%% overview

def create_overview(results_dir, output='overview.png', cols=4):
    files = sorted(f for f in os.listdir(results_dir) 
                   if f.endswith('.png') and f != output)
    num = len(files)
    rows = math.ceil(num / cols)
    fig, axes = plt.subplots(rows, cols, figsize=(cols * 2, rows * 2))
    axes = axes.flatten()

    for ax in axes[num:]:
        ax.axis('off')

    for i, (fname, ax) in enumerate(zip(files, axes)):
        img_path = os.path.join(results_dir, fname)
        img = Image.open(img_path)
        ax.imshow(img)
        ax.axis('off')
        label = os.path.splitext(fname)[0].replace('_', '\n')
        ax.set_title(label, fontsize=8)

    plt.tight_layout()
    out_path = os.path.join(results_dir, output)
    plt.savefig(out_path, dpi=300)
    plt.show()

create_overview(results_dir)
overview_path = r'c:\Ribasim9\icon_maker\results\overview.png'

# cnvert to grayscale
img = Image.open(overview_path).convert('L')
plt.imshow(img, cmap='gray')
plt.axis('off')
plt.title("Grayscale Simulation (Achromatopsia)")
plt.show()

#%% 12x12 png icons from existing svgs

small_icon_dir = os.path.join(results_dir, 'small_png')
os.makedirs(small_icon_dir, exist_ok=True)

for file in os.listdir(results_dir):
    if file.endswith(".svg"):
        svg_path = os.path.join(results_dir, file)
        png_path = os.path.join(small_icon_dir, file.replace('.svg', '.png'))

        # svg to 12x12 png
        cairosvg.svg2png(url=svg_path, write_to=png_path,
                         output_width=36, output_height=36)

print(f" png icons saved to: {small_icon_dir}")


