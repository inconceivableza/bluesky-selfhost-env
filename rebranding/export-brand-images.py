#!/bin/sh
"exec" """$(dirname $0)/venv/bin/python""" "$0" "$@" # this is a shell exec which will drop down to the relative virtualenv's python

import logging
import os
import subprocess
import sys
import tempfile
from os.path import abspath, basename, dirname, exists, getmtime, join
import compactify_svg
import xml.etree.ElementTree as ET
import re
import math

src_dir = dirname(abspath(__file__))

def find_inkscape_exe():
    if sys.platform.startswith('win'):
        exe_name = 'inkscape.com'
        status, result = subprocess.getstatusoutput(f"{exe_name} -h")
        if status != 0:
            for _parent_path in ["C:\\Program Files", "C:\\Program Files (x86)", "C:\\Program Files\\WindowsApps"]:
                potential_path = join(_parent_path, "Inkscape", "bin", exe_name)
                if exists(potential_path):
                    return potential_path
        return exe_name
    else:
        return 'inkscape'

exe_name = find_inkscape_exe()
magick_prefix = ["magick"] if sys.platform.startswith('win') else []

force_recreate=False

def should_recreate(source_file, target_file):
    """
    Check if target should be recreated based on source timestamp (like Make).
    """
    if not exists(source_file):
        raise FileNotFoundError(f"Source file does not exist: {source_file}")
    if not exists(target_file):
        return True
    if force_recreate:
        return True
    source_mtime = getmtime(source_file)
    target_mtime = getmtime(target_file)
    return source_mtime > target_mtime

text_dim_cache = {}

def get_text_dimensions(text_args, text):
    text_args = tuple(text_args)
    if (text_args, text) in text_dim_cache:
        return text_dim_cache[text_args, text]
    output = subprocess.check_output(["magick"] + list(text_args) + ['label:%s' % text, '-format', '%wx%h', 'info:'], encoding='utf-8')
    if 'x' in output:
        ws, hs = output.strip().split('x', 1)
        w, h = int(ws), int(hs)
        text_dim_cache[text_args, text] = (w, h)
        return w, h
    raise ValueError("Error getting text dimensions with imagemagick: %s" % error)

def add_badges(src_id, src_dir, src_ext, badges={}):
    src_path = join(src_dir, f"{src_id}.{src_ext}")
    src_info = subprocess.check_output(magick_prefix + ['identify', src_path]).decode('utf-8').strip().split()
    src_width, src_height = [int(s) for s in src_info[2].split('x', 1)]
    diagonal = math.sqrt(src_width**2 + src_height**2)
    circle_radius = int(diagonal * 0.33)
    if (circle_radius < 16): circle_radius = max(8, int(diagonal/3))
    point_size = "%d" % int((circle_radius * 0.9 * 72) / 300)
    stroke_width = "%d" % int(circle_radius / 16)
    padding = int(circle_radius * 0.25)
    print(f"Source width {src_width} height {src_height} pixel size {circle_radius} point size {point_size}")
    font_args = ["-font", "Roboto-Mono-Bold", "-density", "300", "-pointsize", point_size]
    circle_center = src_width - padding - circle_radius/2, src_height - padding - circle_radius/2
    circle_edge = src_width - padding - circle_radius, src_height - padding - circle_radius/2
    format_point = lambda xy: f'{xy[0]},{xy[1]}'
    badge_args = ["-fill", "white", "-stroke", "black", "-strokewidth", stroke_width, "-draw"]
    for suffix, badge in badges.items():
        if not (badge.isalnum() and suffix.isalnum()):
           raise ValueError(f"Invalid badge {badge} or suffix {suffix}")
        badge_path = join(src_dir, f"{src_id}.{suffix}.{src_ext}")
        if True or should_recreate(src_path, badge_path):
            logging.info(f"Adding badge {badge} to {badge_path}")
            text_dims = get_text_dimensions(font_args, badge)
            text_location = circle_center[0] - text_dims[0]/2, circle_center[1] - text_dims[1]/2
            print(["magick", src_path] + font_args + badge_args + [f"text {format_point(text_location)} '{badge}'", badge_path])
            subprocess.run(["magick", src_path] + font_args + badge_args + [f"gravity NorthWest text {format_point(text_location)} '{badge}'", badge_path])

def inkscape_convert(src_path, src_id, target_dir, target_ext, id_only=False, badges={}):
    exportargs = []
    target_path = join(target_dir, f"{src_id}.{target_ext}")
    if should_recreate(src_path, target_path):
        if target_ext == "svg":
            exportargs.append('--export-plain-svg')
        if id_only:
            exportargs.extend([
                f'--actions=select:{src_id};clone-unlink;export-text-to-path',
                '--export-id-only',
            ])
        logging.info(f"Extracting {src_path}:{src_id} to {target_path}")
        subprocess.run([exe_name, f"--export-type={target_ext}", f"--export-id={src_id}"] + exportargs + [f"--export-filename={target_path}", src_path])
    add_badges(src_id, target_dir, target_ext, badges)

def parse_css_styles(css_string):
    styles = {}
    # Split the string by semicolons to get individual style declarations
    declarations = css_string.split(';')
    for declaration in declarations:
        if not declaration.strip():
            continue
        # Split each declaration into property and value
        parts = declaration.split(':', 1)
        if len(parts) == 2:
            property_name = parts[0].strip()
            value = parts[1].strip()
            styles[property_name] = value
    return styles

def get_gradient_id(styles):
    # Extract gradient id if fill uses url() format
    fill_value = styles.get('fill', '')
    gradient_match = re.search(r'url\(#([a-zA-Z0-9_]+)\)', fill_value)
    if gradient_match:
        return gradient_match.group(1)
    return None

float_p = r'[-+]?(?:[0-9]+(?:\.[0-9]+)?|\.[0-9]+)(?:e[+-]?[0-9]+)?'
translate_re = re.compile(rf'translate\(({float_p}),\s*({float_p})\)')

def apply_translate_transform(transform_str, x1, y1, x2, y2):
    translate_m = translate_re.match(transform_str)
    if not translate_m:
        raise ValueError(f"Invalid translate transform format '{transform_str}'. Expected: translate(x,y)")
    trans_x, trans_y = translate_m.group(1), translate_m.group(2)
    trans_x, trans_y = float(trans_x), float(trans_y)
    new_x1, new_x2 = x1 + trans_x, x2 + trans_x
    new_y1, new_y2 = y1 + trans_y, y2 + trans_y
    return new_x1, new_y1, new_x2, new_y2

matrix_re = re.compile(rf'matrix\(({float_p}),\s*({float_p}),\s*({float_p}),\s*({float_p}),\s*({float_p}),\s*({float_p})\)')

def apply_matrix_transform(transform_str, x1, y1, x2, y2):
    matrix_m = matrix_re.match(transform_str)
    if not matrix_m:
        raise ValueError(f"Invalid matrix transform format '{transform_str}'. Expected: matrix(a,b,c,d,e,f)")
    # Parse the matrix coefficients
    a, b, c, d, e, f = map(float, matrix_m.groups())
    # Apply the transform to the coordinates
    # [x'] = [a c e] [x]
    # [y'] = [b d f] [y]
    # [1 ] = [0 0 1] [1]
    new_x1 = a * x1 + c * y1 + e
    new_y1 = b * x1 + d * y1 + f
    new_x2 = a * x2 + c * y2 + e
    new_y2 = b * x2 + d * y2 + f
    return new_x1, new_y1, new_x2, new_y2

def get_relative_gradient_vector(gradient_def, source_element, target_element):
    """Given absolutely positioned gradient and rectangle, translate the gradient definition from the source to the target element"""
    def get_float(d, k):
        v = d.get(k)
        return float(v) if v is not None else None
    grad_x1, grad_y1, grad_x2, grad_y2 = [get_float(gradient_def, key) for key in ('x1', 'y1', 'x2', 'y2')]
    if 'gradientTransform' in gradient_def.attrib:
        transform = gradient_def.get('gradientTransform')
        if transform.startswith('translate'):
            grad_x1, grad_y1, grad_x2, grad_y2 = apply_translate_transform(transform, grad_x1, grad_y1, grad_x2, grad_y2)
            del gradient_def.attrib['gradientTransform']
        elif transform.startswith('matrix'):
            grad_x1, grad_y1, grad_x2, grad_y2 = apply_matrix_transform(transform, grad_x1, grad_y1, grad_x2, grad_y2)
            del gradient_def.attrib['gradientTransform']
        else:
            raise ValueError(f"Unknown transform, cannot apply: {transform}")
    src_x, src_y, src_width, src_height = [get_float(source_element, key) for key in ('x', 'y', 'width', 'height')]
    tgt_x, tgt_y, tgt_width, tgt_height = [get_float(target_element, key) for key in ('x', 'y', 'width', 'height')]
    relgrad_x1, relgrad_x2, relgrad_y1, relgrad_y2 = [(grad_x1 - src_x) / src_width, (grad_x2 - src_x) / src_width,
                                                      (grad_y1 - src_y) / src_height, (grad_y2 - src_y) / src_height]
    tgtgrad_x1, tgtgrad_x2, tgtgrad_y1, tgtgrad_y2 = [tgt_x + relgrad_x1 * tgt_width, tgt_x + relgrad_x2 * tgt_width,
                                                      tgt_y + relgrad_y1 * tgt_height, tgt_y + relgrad_y2 * tgt_height]
    return {'x1': tgtgrad_x1, 'x2': tgtgrad_x2, 'y1': tgtgrad_y1, 'y2': tgtgrad_y2}

def copy_style_between_elements(svg_string, source_id, target_id):
    """
    Copy the style attribute from one SVG element to another.

    Args:
        svg_string (str): The SVG content as a string
        source_id (str): ID of the element to copy style from
        target_id (str): ID of the element to apply the style to

    Returns:
        str: Modified SVG string with the style copied
    """
    # Add namespace to prevent ET from adding ns0 prefixes
    ET.register_namespace("", "http://www.w3.org/2000/svg")
    try:
        root = ET.fromstring(svg_string)
    except ET.ParseError as e:
        raise ValueError(f"Error parsing SVG: {e}")
    # Find both elements by ID
    element_id_map = {}
    for elem in root.iter():
        element_id = elem.get('id')
        if element_id:
            element_id_map[element_id] = elem
    source_element, target_element = element_id_map.get(source_id), element_id_map.get(target_id)
    if source_element is None:
        raise ValueError(f"Source element with id '{source_id}' not found")
    if target_element is None:
        raise ValueError(f"Target element with id '{target_id}' not found")
    if target_element.tag.endswith('use'):
        # if the target is actually a reference, affect the base style, since we assume only this reference is being exported
        target_ref_id = target_element.get('{http://www.w3.org/1999/xlink}href').replace('#', '')
        target_element = element_id_map.get(target_ref_id)
    style = source_element.get('style') or ''
    styles_dict = parse_css_styles(style)
    gradient_id = get_gradient_id(styles_dict)
    if gradient_id:
        gradient_def = element_id_map.get(gradient_id)
        target_gradient_coords = get_relative_gradient_vector(gradient_def, source_element, target_element)
        for coord_key, coord_value in target_gradient_coords.items():
            gradient_def.set(coord_key, str(coord_value))
    target_style = target_element.get('style') or ''
    logging.info(f"Changing style of {target_id} from {target_style} to {style} to match {source_id}")
    target_element.set('style', style)
    return ET.tostring(root, encoding='unicode')

def inkscape_export_app_icons(src_path, src_id, target_dir, target_ext, target_id_bases, theme_style_id_bases, badges={}):
    with open(src_path, 'rb') as f:
        svg_src = f.read()
    orig_src_path = src_path
    exportargs = []
    if target_ext == "svg":
        exportargs.append('--export-plain-svg')
    exportactions = [
        f"select-by-id:{src_id}",
        "clone-unlink",
        "export-text-to-path"
    ]
    exportargs.append(f'--actions={";".join(exportactions)}')
    exportargs.extend([
            '--export-id-only',
        ])
    for target_id, theme_style_id_base in zip(target_id_bases, theme_style_id_bases):
        target_path = join(target_dir, f"{target_id}.{target_ext}")
        if should_recreate(orig_src_path, target_path):
            tmp_file = None
            if theme_style_id_base:
                new_svg_src = copy_style_between_elements(svg_src, f"{theme_style_id_base}_bg", f"{src_id}_bg")
                # this repeats the operation for the foreground element, but ignores failures as most don't have a foreground element
                try:
                    new_svg_src = copy_style_between_elements(new_svg_src, f"{theme_style_id_base}_fg", f"{src_id}_icon")
                except ValueError as e:
                    pass # ignore there not being a foreground style to copy
                tmp_file = tempfile.NamedTemporaryFile(prefix=basename(orig_src_path).replace('.svg', '')+'-'+target_id, suffix=".svg", delete_on_close=False, mode='w')
                tmp_file.write(new_svg_src)
                tmp_file.close()
                src_path = tmp_file.name
            else:
                src_path = orig_src_path
            logging.info(f"Extracting {src_path}:{src_id} to {target_path}")
            args = [exe_name, f"--export-type={target_ext}", f"--export-id={src_id}"] + exportargs + [f"--export-filename={target_path}", src_path]
            logging.debug(f"Extraction command: {' '.join(args)}")
            subprocess.run(args)
            if tmp_file:
                os.unlink(tmp_file.name)
        add_badges(target_id, target_dir, target_ext, badges)

def wait_for_file(look_for_file, max_looks=20):
    t = 0
    while t < max_looks:
        if os.exist(look_for_file):
            return True
        time.sleep(1)
        t += 1
    return os.exist(look_for_file)

def compactify(src_path, target_path):
    if not should_recreate(src_path, target_path):
        return
    compactify_svg.compactify(src_path, target_path)

def export_images(src, target_dir, force=False, badges={}):
    inkscape_convert(src, 'splash-dark', target_dir, 'png', badges=badges)
    inkscape_convert(src, 'splash', target_dir, 'png', badges=badges)
    inkscape_convert(src, 'splash-android-icon-dark', target_dir, 'png', badges=badges)
    inkscape_convert(src, 'splash-android-icon', target_dir, 'png', badges=badges)
    inkscape_convert(src, 'default-avatar', target_dir, 'png')
    inkscape_convert(src, 'logo', target_dir, 'png')
    inkscape_convert(src, 'icon', target_dir, 'png')
    inkscape_convert(src, 'icon-android-background', target_dir, 'png', id_only=True)
    inkscape_convert(src, 'icon-android-foreground', target_dir, 'png', id_only=True, badges=badges)
    inkscape_convert(src, 'icon-android-notification', target_dir, 'png', badges=badges)
    inkscape_convert(src, 'favicon', target_dir, 'png', badges=badges)
    inkscape_convert(src, 'favicon-32x32', target_dir, 'png', badges=badges)
    inkscape_convert(src, 'favicon-16x16', target_dir, 'png', badges=badges)
    inkscape_convert(src, 'apple-touch-icon', target_dir, 'png')
    inkscape_convert(src, 'social-card-default', target_dir, 'png')
    inkscape_convert(src, 'social-card-default-gradient', target_dir, 'png')
    inkscape_convert(src, 'safari-pinned-tab', target_dir, 'svg', id_only=True)
    inkscape_convert(src, 'Logotype', target_dir, 'svg', id_only=True)
    inkscape_convert(src, 'icon', target_dir, 'svg', id_only=True)
    inkscape_convert(src, 'logo', target_dir, 'svg', id_only=True)
    inkscape_convert(src, 'email_logo_default', target_dir, 'png')
    inkscape_convert(src, 'email_mark_dark', target_dir, 'png')
    inkscape_convert(src, 'email_mark_light', target_dir, 'png')
    compactify(join(target_dir, 'safari-pinned-tab.svg'), join(target_dir, 'safari-pinned-tab.compact.svg'))
    compactify(join(target_dir, 'Logotype.svg'), join(target_dir, 'Logotype.compact.svg'))
    (join(target_dir, 'icon.svg'), join(target_dir, 'icon.compact.svg'))
    compactify(join(target_dir, 'logo.svg'), join(target_dir, 'logo.compact.svg'))
    # app icon themes; aurora is used as the base and the others have their styles copied on before export
    inkscape_convert(src, 'android_icon_core_aurora', target_dir, 'png', id_only=True, badges=badges)
    inkscape_convert(src, 'ios_icon_core_aurora', target_dir, 'png', id_only=True, badges=badges)
    icon_themes = ['core_bonfire', 'core_classic', 'core_flat_black', 'core_flat_blue', 'core_flat_white', 'core_midnight', 'core_sunrise', 'core_sunset', 'default_dark', 'default_light', 'default_next']
    for os in ['android', 'ios']:
        target_id_bases = [f'{os}_icon_{icon_theme}' for icon_theme in icon_themes]
        theme_style_id_bases = [f'app_icon_theme_{icon_theme}' for icon_theme in icon_themes]
        inkscape_export_app_icons(src, f'{os}_icon_core_aurora', target_dir, 'png', target_id_bases, theme_style_id_bases, badges=badges)


def show_files(target_dir):
    for filename in os.listdir(target_dir):
        subprocess.run(magick_prefix + ["identify", filename], cwd=target_dir)

if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('-f', '--force', action="store_true", help="Force regeneration of images even if newer than source")
    parser.add_argument('src_image', help="A branding image with the necessary ids to generate all the required images")
    parser.add_argument('target_dir', default=None, nargs='?', help="Where the generated images should be written (default: `dirname src_image`/generated)")
    args = parser.parse_args()
    logging.getLogger().setLevel(logging.INFO)
    if not exists(args.src_image):
        parser.error(f"Could not find source image {args.src_image}")
    if not args.target_dir:
        args.target_dir = join(dirname(args.src_image), "generated")
    if not os.path.exists(args.target_dir):
        os.makedirs(args.target_dir)
    if args.force:
        force_recreate = True # global variable to stop having to pass this everywhere
    badges = {'development': 'D', 'preview': 'P', 'testflight': 'T'}
    export_images(args.src_image, args.target_dir, badges=badges)
    # show_files(args.target_dir)

