"""Export the report to a real Word document using only Python's standard library."""

from datetime import datetime, timezone
from pathlib import Path
import re
import sys
import struct
from xml.sax.saxutils import escape
import xml.etree.ElementTree as ET
from zipfile import ZIP_DEFLATED, ZipFile


W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
XML = 'http://www.w3.org/XML/1998/namespace'
ET.register_namespace('w', W)
ET.register_namespace('r', R)
WP = 'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing'
A = 'http://schemas.openxmlformats.org/drawingml/2006/main'
PIC = 'http://schemas.openxmlformats.org/drawingml/2006/picture'
for prefix, namespace in [('wp', WP), ('a', A), ('pic', PIC)]:
    ET.register_namespace(prefix, namespace)


def image_paragraph(parent, caption, image_path, images):
    payload = image_path.read_bytes()
    if not payload.startswith(b'\x89PNG\r\n\x1a\n'):
        raise ValueError(f'Only PNG images are supported: {image_path}')
    width, height = struct.unpack('>II', payload[16:24])
    index = len(images) + 1
    images.append(payload)
    cx = 6120000
    cy = round(cx * height / width)
    element = node(parent, 'p')
    drawing = node(node(element, 'r'), 'drawing')
    def draw(parent, namespace, tag, **attributes):
        return ET.SubElement(parent, f'{{{namespace}}}{tag}', {key: str(value) for key, value in attributes.items()})
    inline = draw(drawing, WP, 'inline', distT=0, distB=0, distL=0, distR=0)
    draw(inline, WP, 'extent', cx=cx, cy=cy)
    draw(inline, WP, 'docPr', id=index, name=caption, descr=caption)
    draw(draw(inline, WP, 'cNvGraphicFramePr'), A, 'graphicFrameLocks', noChangeAspect=1)
    graphic = draw(inline, A, 'graphic')
    data = draw(graphic, A, 'graphicData', uri=PIC)
    picture = draw(data, PIC, 'pic')
    nonvisual = draw(picture, PIC, 'nvPicPr')
    draw(nonvisual, PIC, 'cNvPr', id=index, name=caption)
    draw(nonvisual, PIC, 'cNvPicPr')
    fill = draw(picture, PIC, 'blipFill')
    blip = draw(fill, A, 'blip')
    blip.set(f'{{{R}}}embed', f'rIdImage{index}')
    draw(draw(fill, A, 'stretch'), A, 'fillRect')
    shape = draw(picture, PIC, 'spPr')
    transform = draw(shape, A, 'xfrm')
    draw(transform, A, 'off', x=0, y=0)
    draw(transform, A, 'ext', cx=cx, cy=cy)
    draw(draw(shape, A, 'prstGeom', prst='rect'), A, 'avLst')
    paragraph(parent, caption, size=20)


def node(parent, name, **attributes):
    return ET.SubElement(parent, f'{{{W}}}{name}', {
        f'{{{W}}}{key}': str(value) for key, value in attributes.items()
    })


def run(parent, text, code=False, bold=False, size=None):
    element = node(parent, 'r')
    if code or bold or size:
        props = node(element, 'rPr')
        if code:
            node(props, 'rFonts', ascii='Consolas', hAnsi='Consolas', cs='Consolas')
        if bold:
            node(props, 'b')
        if size:
            node(props, 'sz', val=size)
            node(props, 'szCs', val=size)
    content = node(element, 't')
    content.set(f'{{{XML}}}space', 'preserve')
    content.text = text


def paragraph(parent, text='', style=None, bold=False, size=None):
    element = node(parent, 'p')
    props = node(element, 'pPr')
    if style:
        node(props, 'pStyle', val=style)
    if size:
        node(props, 'spacing', after=40)
        node(props, 'jc', val='left')
    for part in re.split(r'(`[^`]+`)', text):
        if part:
            code = part.startswith('`') and part.endswith('`')
            run(element, part[1:-1] if code else part, code, bold, size)
    return element


def table(parent, rows):
    count = len(rows[0])
    width = 9638  # A4 portrait, margins 2 cm.
    if count == 4:
        widths = [700, 2700, 3800, 2438]
    elif count == 3:
        widths = [2700, 2600, 4338]
    else:
        widths = [2800, width - 2800] if count == 2 else [width // count] * count
    element = node(parent, 'tbl')
    props = node(element, 'tblPr')
    node(props, 'tblW', w=width, type='dxa')
    node(props, 'tblLayout', type='fixed')
    borders = node(props, 'tblBorders')
    for side in ['top', 'left', 'bottom', 'right', 'insideH', 'insideV']:
        node(borders, side, val='single', sz=4, color='B5C4C1')
    margins = node(props, 'tblCellMar')
    for side in ['top', 'left', 'bottom', 'right']:
        node(margins, side, w=85, type='dxa')
    grid = node(element, 'tblGrid')
    for cell_width in widths:
        node(grid, 'gridCol', w=cell_width)
    for index, row in enumerate(rows):
        if len(row) != count:
            raise ValueError('Unequal Markdown table row lengths')
        row_element = node(element, 'tr')
        row_props = node(row_element, 'trPr')
        node(row_props, 'cantSplit')
        if index == 0:
            node(row_props, 'tblHeader')
        for text, cell_width in zip(row, widths):
            cell = node(row_element, 'tc')
            cell_props = node(cell, 'tcPr')
            node(cell_props, 'tcW', w=cell_width, type='dxa')
            node(cell_props, 'vAlign', val='center')
            if index == 0:
                node(cell_props, 'shd', fill='DFECE8', val='clear')
            paragraph(cell, text, bold=index == 0, size=18)
    paragraph(parent)


def styles():
    root = ET.Element(f'{{{W}}}styles')
    defaults = node(root, 'docDefaults')
    default_run = node(node(defaults, 'rPrDefault'), 'rPr')
    node(default_run, 'rFonts', ascii='Times New Roman', hAnsi='Times New Roman', cs='Times New Roman')
    node(default_run, 'sz', val=24)
    node(default_run, 'szCs', val=24)
    node(default_run, 'lang', val='ru-RU')
    default_paragraph = node(node(defaults, 'pPrDefault'), 'pPr')
    node(default_paragraph, 'spacing', after=120, line=276, lineRule='auto')

    definitions = [
        ('Normal', 'Normal', 24, None),
        ('Title', 'Title', 34, None),
        ('Heading1', 'heading 1', 28, 0),
        ('Heading2', 'heading 2', 25, 1),
        ('Code', 'Code', 18, None),
    ]
    for style_id, name, font_size, level in definitions:
        element = node(root, 'style', type='paragraph', styleId=style_id)
        if style_id == 'Normal':
            element.set(f'{{{W}}}default', '1')
        node(element, 'name', val=name)
        if style_id != 'Normal':
            node(element, 'basedOn', val='Normal')
        props = node(element, 'pPr')
        node(props, 'jc', val='both' if style_id == 'Normal' else 'left')
        if style_id in {'Title', 'Heading1', 'Heading2'}:
            node(props, 'keepNext')
            node(props, 'keepLines')
            node(props, 'spacing', before=240, after=160)
            if level is not None:
                node(props, 'outlineLvl', val=level)
        if style_id == 'Code':
            node(props, 'spacing', after=0, line=240, lineRule='auto')
            node(props, 'shd', fill='F1F4F3', val='clear')
        font = node(element, 'rPr')
        node(font, 'sz', val=font_size)
        node(font, 'szCs', val=font_size)
        if style_id in {'Title', 'Heading1', 'Heading2'}:
            node(font, 'b')
        if style_id == 'Code':
            node(font, 'rFonts', ascii='Consolas', hAnsi='Consolas', cs='Consolas')
    return root


def document(markdown, source, images):
    root = ET.Element(f'{{{W}}}document')
    body = node(root, 'body')
    lines = markdown.splitlines()
    index = 0
    while index < len(lines):
        line = lines[index].strip()
        if not line:
            index += 1
            continue
        if line.startswith('```'):
            index += 1
            while index < len(lines) and not lines[index].strip().startswith('```'):
                # Code paragraphs keep their original whitespace and arrows.
                element = node(body, 'p')
                props = node(element, 'pPr')
                node(props, 'pStyle', val='Code')
                if index + 1 < len(lines) and not lines[index + 1].strip().startswith('```'):
                    node(props, 'keepNext')
                run(element, lines[index])
                index += 1
            if index == len(lines):
                raise ValueError('Unclosed Markdown code fence')
            paragraph(body)
        elif line.startswith('!['):
            match = re.fullmatch(r'!\[(.+)\]\((.+)\)', line)
            if not match:
                raise ValueError(f'Invalid image: {line}')
            image_paragraph(body, match[1], (source.parent / match[2]).resolve(), images)
        elif line.startswith('|'):
            rows = []
            while index < len(lines) and lines[index].strip().startswith('|'):
                parts = [cell.strip() for cell in lines[index].strip().strip('|').split('|')]
                if not all(re.fullmatch(r':?-+:?', cell) for cell in parts):
                    rows.append(parts)
                index += 1
            table(body, rows)
            continue
        elif line.startswith('#'):
            match = re.fullmatch(r'(#{1,3})\s+(.+)', line)
            if not match:
                raise ValueError(f'Unsupported heading: {line}')
            style = ['Title', 'Heading1', 'Heading2'][len(match[1]) - 1]
            paragraph(body, match[2], style)
        else:
            parts = [line]
            index += 1
            while index < len(lines) and lines[index].strip() and not lines[index].strip().startswith(('#', '|', '```', '![')):
                parts.append(lines[index].strip())
                index += 1
            paragraph(body, ' '.join(parts))
            continue
        index += 1
    section = node(body, 'sectPr')
    footer = node(section, 'footerReference', type='default')
    footer.set(f'{{{R}}}id', 'rIdFooter')
    node(section, 'pgSz', w=11906, h=16838)
    node(section, 'pgMar', top=1134, right=1134, bottom=1134, left=1134, header=567, footer=567, gutter=0)
    return root


def serialize(element):
    return ET.tostring(element, encoding='utf-8', xml_declaration=True)


def main():
    project = Path(__file__).resolve().parent.parent
    source = Path(sys.argv[1]) if len(sys.argv) > 1 else project / 'docs/pr4-api-report.md'
    target = Path(sys.argv[2]) if len(sys.argv) > 2 else source.with_suffix('.docx')
    if target.exists():
        raise FileExistsError(f'Refusing to overwrite existing document: {target}')
    markdown = source.read_text(encoding='utf-8-sig')
    images = []
    doc = document(markdown, source, images)
    title = next((line.lstrip('#').strip() for line in markdown.splitlines() if line.startswith('# ')), source.stem)
    footer = ET.Element(f'{{{W}}}ftr')
    page = paragraph(footer)
    node(page.find(f'{{{W}}}pPr'), 'jc', val='center')
    field = node(page, 'fldSimple', instr='PAGE')
    run(field, '1', size=20)
    now = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    entries = {
        '[Content_Types].xml': '''<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
<Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>
<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
</Types>''',
        '_rels/.rels': '''<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rIdDocument" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
<Relationship Id="rIdCore" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
<Relationship Id="rIdApp" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
</Relationships>''',
        'word/_rels/document.xml.rels': '''<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
<Relationship Id="rIdFooter" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>
</Relationships>''',
        'word/document.xml': serialize(doc),
        'word/styles.xml': serialize(styles()),
        'word/footer1.xml': serialize(footer),
        'docProps/core.xml': f'''<?xml version="1.0" encoding="UTF-8"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
<dc:title>{escape(title)}</dc:title>
<dc:subject>Аптечный каталог. Учебный отчёт.</dc:subject>
<dc:language>ru-RU</dc:language>
<dcterms:created xsi:type="dcterms:W3CDTF">{now}</dcterms:created>
<dcterms:modified xsi:type="dcterms:W3CDTF">{now}</dcterms:modified>
</cp:coreProperties>''',
        'docProps/app.xml': '''<?xml version="1.0" encoding="UTF-8"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"><Application>Pharmacy report exporter</Application></Properties>''',
    }
    for value in entries.values():
        ET.fromstring(value)
    if images:
        entries['[Content_Types].xml'] = entries['[Content_Types].xml'].replace('</Types>',
            '<Default Extension="png" ContentType="image/png"/></Types>')
        relationships = ''.join(f'<Relationship Id="rIdImage{index}" Type="{R}/image" Target="media/image{index}.png"/>'
            for index in range(1, len(images) + 1))
        entries['word/_rels/document.xml.rels'] = entries['word/_rels/document.xml.rels'].replace('</Relationships>', relationships + '</Relationships>')
        entries.update({f'word/media/image{index}.png': payload for index, payload in enumerate(images, 1)})
    target.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(target, 'w', compression=ZIP_DEFLATED) as archive:
        for name, value in entries.items():
            archive.writestr(name, value.encode('utf-8') if isinstance(value, str) else value)
    with ZipFile(target) as archive:
        assert archive.testzip() is None
        restored = ET.fromstring(archive.read('word/document.xml'))
        tables = restored.findall(f'.//{{{W}}}tbl')
        expected_tables = sum(1 for line in markdown.splitlines() if re.match(r'^\|\s*:?-+:?\s*\|', line))
        assert len(tables) == expected_tables, f'Expected {expected_tables} report tables, got {len(tables)}'
        text = ''.join(restored.itertext())
        assert title in text
        for index in range(1, len(images) + 1):
            assert archive.read(f'word/media/image{index}.png').startswith(b'\x89PNG')
    print(f'Created: {target}')
    print(f'Checked: valid DOCX ZIP, XML parts, {len(tables)} tables, {len(images)} embedded images.')


if __name__ == '__main__':
    main()
