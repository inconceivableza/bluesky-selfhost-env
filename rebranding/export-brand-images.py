#!/usr/bin/env -S sh -c 'exec "`dirname "$0"`/venv/bin/python" "$0" "$@"'

import logging
import os
import subprocess
import sys
import tempfile
from os.path import abspath, basename, dirname, exists, join
import compactify_svg
import xml.etree.ElementTree as ET
import re

src_dir = dirname(abspath(__file__))
# if exist "{src_dir}\script-env.cmd" call "{src_dir}\script-env.cmd"
exe_name = 'inkscape.com' if sys.platform.startswith('win') else 'inkscape'
magick_prefix = ["magick"] if sys.platform.startswith('win') else []

def inkscape_convert(src_path, src_id, target_dir, target_ext, id_only=False):
    exportargs = []
    if target_ext == "svg":
        exportargs.append('--export-plain-svg')
    if id_only:
        exportargs.extend([
            f'--actions=select:{src_id};clone-unlink;export-text-to-path',
            '--export-id-only',
        ])
    logging.info(f"Extracting {src_path}:{src_id} to {target_dir}/{src_id}.{target_ext}")
    subprocess.run([exe_name, f"--export-type={target_ext}", f"--export-id={src_id}"] + exportargs + [f"--export-filename={join(target_dir, src_id)}.{target_ext}", src_path])

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

translate_re = re.compile('translate\\(([0-9.-]*),([0-9.-]*)\\)')
def get_relative_gradient_vector(gradient_def, source_element, target_element):
    """Given absolutely positioned gradient and rectangle, translate the gradient definition from the source to the target element"""
    def get_float(d, k):
        v = d.get(k)
        return float(v) if v is not None else None
    grad_x1, grad_x2, grad_y1, grad_y2 = [get_float(gradient_def, key) for key in ('x1', 'x2', 'y1', 'y2')]
    if 'gradientTransform' in gradient_def.attrib:
        transform = gradient_def.get('gradientTransform')
        translate_m = translate_re.match(transform)
        if translate_m:
            trans_x, trans_y = translate_m.group(1), translate_m.group(2)
            trans_x, trans_y = float(trans_x), float(trans_y)
            grad_x1, grad_x2 = grad_x1 + trans_x, grad_x2 + trans_x
            grad_y1, grad_y2 = grad_y1 + trans_y, grad_y2 + trans_y
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

def inkscape_export_app_icons(src_path, src_id, target_dir, target_ext, target_id_bases, theme_style_id_bases):
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
        logging.info(f"Extracting {src_path}:{src_id} to {target_dir}/{target_id}.{target_ext}")
        args = [exe_name, f"--export-type={target_ext}", f"--export-id={src_id}"] + exportargs + [f"--export-filename={join(target_dir, target_id)}.{target_ext}", src_path]
        logging.debug(f"Extraction command: {' '.join(args)}")
        subprocess.run([exe_name, f"--export-type={target_ext}", f"--export-id={src_id}"] + exportargs + [f"--export-filename={join(target_dir, target_id)}.{target_ext}", src_path])
        if tmp_file:
            os.unlink(tmp_file.name)

def wait_for_file(look_for_file, max_looks=20):
    t = 0
    while t < max_looks:
        if os.exist(look_for_file):
            return True
        time.sleep(1)
        t += 1
    return os.exist(look_for_file)

def export_images(src, target_dir):
    inkscape_convert(src, 'splash-dark', target_dir, 'png')
    inkscape_convert(src, 'splash', target_dir, 'png')
    inkscape_convert(src, 'splash-android-icon-dark', target_dir, 'png')
    inkscape_convert(src, 'splash-android-icon', target_dir, 'png')
    inkscape_convert(src, 'default-avatar', target_dir, 'png')
    inkscape_convert(src, 'logo', target_dir, 'png')
    inkscape_convert(src, 'icon', target_dir, 'png')
    inkscape_convert(src, 'icon-android-background', target_dir, 'png', id_only=True)
    inkscape_convert(src, 'icon-android-foreground', target_dir, 'png', id_only=True)
    inkscape_convert(src, 'icon-android-notification', target_dir, 'png')
    inkscape_convert(src, 'favicon', target_dir, 'png')
    inkscape_convert(src, 'favicon-32x32', target_dir, 'png')
    inkscape_convert(src, 'favicon-16x16', target_dir, 'png')
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
    compactify_svg.compactify(join(target_dir, 'safari-pinned-tab.svg'), join(target_dir, 'safari-pinned-tab.compact.svg'))
    compactify_svg.compactify(join(target_dir, 'Logotype.svg'), join(target_dir, 'Logotype.compact.svg'))
    compactify_svg.compactify(join(target_dir, 'icon.svg'), join(target_dir, 'icon.compact.svg'))
    compactify_svg.compactify(join(target_dir, 'logo.svg'), join(target_dir, 'logo.compact.svg'))
    icon_themes = ['core_bonfire', 'core_classic', 'core_flat_black', 'core_flat_blue', 'core_flat_white', 'core_midnight', 'core_sunrise', 'core_sunset', 'default_dark', 'default_light']
    for os in ['android', 'ios']:
        target_id_bases = [f'{os}_icon_{icon_theme}' for icon_theme in icon_themes]
        theme_style_id_bases = [f'app_icon_theme_{icon_theme}' for icon_theme in icon_themes]
        inkscape_export_app_icons(src, f'{os}_icon_core_aurora', target_dir, 'svg', target_id_bases, theme_style_id_bases)

def show_files(target_dir):
    for filename in os.listdir(target_dir):
        subprocess.run(magick_prefix + ["identify", filename], cwd=target_dir)

if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
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
    export_images(args.src_image, args.target_dir)
    show_files(args.target_dir)

