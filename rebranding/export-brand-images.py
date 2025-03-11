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
    source_element = None
    target_element = None
    for elem in root.iter():
        if elem.get('id') == source_id:
            source_element = elem
        elif elem.get('id') == target_id:
            target_element = elem
    if source_element is None:
        raise ValueError(f"Source element with id '{source_id}' not found")
    if target_element is None:
        raise ValueError(f"Target element with id '{target_id}' not found")
    style = source_element.get('style') or ''
    target_style = target_element.get('style') or ''
    logging.info(f"Changing style of {target_id} from {target_style} to {style} to match {source_id}")
    target_element.set('style', style)
    return ET.tostring(root, encoding='unicode')

def inkscape_export_app_icons(src_path, src_id, target_dir, target_ext, target_ids, bg_rect_style_src_ids):
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
    for target_id, bg_rect_style_src_id in zip(target_ids, bg_rect_style_src_ids):
        tmp_file = None
        if bg_rect_style_src_id:
            # TODO: adjust linked gradient offset to match the correct width and height...
            new_svg_src = copy_style_between_elements(svg_src, bg_rect_style_src_id, f"{src_id}_bg")
            tmp_file = tempfile.NamedTemporaryFile(prefix=basename(src_path).replace('.svg', '')+'-'+target_id, suffix=".svg", delete_on_close=False, mode='w')
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
    icon_themes = ['flat_black', 'flat_red', 'bonfire']
    for os in ['android', 'ios']:
        target_ids = [f'{os}_icon_core_{icon_theme}' for icon_theme in icon_themes]
        bg_rect_style_src_ids = [f'app_icon_theme_{icon_theme}' for icon_theme in icon_themes]
        inkscape_export_app_icons(src, f'{os}_icon_core_aurora', target_dir, 'svg', target_ids, bg_rect_style_src_ids)
    return False
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

