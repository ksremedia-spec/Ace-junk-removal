"""Builds "Ace test sheet - Ashley layout (fake data).xlsx" in this folder.

The same columns as Ashley's real Google Sheet (docs/ashley-spreadsheet.md),
filled with made-up people, for trying the import without her file:
Date, Customer Name, # and Street Name, City State & Zip, Price, Form of
Payment, Check #, Not Mailing Address, in a tab "Client Job List", plus an
empty "Contracted Labor" tab. Red price cells mean not paid yet.

Written like a Google Sheets download: shared strings, dates as numbers
shown "m/d" (the first one "m/d/yyyy"), and a red fill style. Uses only the
Python standard library. Seeded, so it comes out the same every run.
Run: python3 test-data/make_ashley_layout_sheet.py
     python3 test-data/make_ashley_layout_sheet.py 600   (exactly 600 jobs,
     most customers once, as in a real year; saved as "... 600 jobs ...")
"""

import datetime as dt
import os
import random
import sys
import zipfile
from xml.sax.saxutils import escape

R = random.Random(20261021)
HERE = os.path.dirname(os.path.abspath(__file__))
JOBS = int(sys.argv[1]) if len(sys.argv) > 1 else None
OUT = os.path.join(HERE, f"Ace test sheet - {JOBS} jobs (fake data).xlsx" if JOBS
                   else "Ace test sheet - Ashley layout (fake data).xlsx")

FIRST = ["Linda", "Mark", "Dave", "Karen", "Paul", "Maria", "Joe", "Susan", "Mike", "Donna", "Steve",
         "Patty", "Kevin", "Lisa", "Brian", "Tina", "Rich", "Carol", "Jim", "Nancy", "Tony", "Diane",
         "Ed", "Janet", "Bob", "Kathy", "Chris", "Dan", "Sharon", "Manny", "Fatima", "Tom", "Rose",
         "Sean", "Ana", "Greg", "Beth", "Al", "Joanne", "Ray"]
LAST = ["Silva", "Pereira", "Medeiros", "Souza", "Costa", "Rego", "Furtado", "Almeida", "Sullivan",
        "Murphy", "Kelly", "Walsh", "Doherty", "Nguyen", "Tran", "Johnson", "Smith", "Brown",
        "Miller", "Davis", "Moore", "Taylor", "Cabral", "Amaral", "Moniz", "Botelho", "Raposo",
        "Tavares", "Fontaine", "Gagnon", "Leblanc", "Pelletier", "Macomber", "Keane", "Pratt"]
STREETS = ["Elm Street", "Main Road", "Bay Road", "Hope Street", "County Street", "Pleasant Street",
           "Highland Avenue", "Cedar Street", "Oak Street", "Maple Avenue", "Shipyard Lane",
           "Ocean Avenue", "Harbor View Drive", "Chestnut Street", "Pine Street", "Locust Street"]
TOWNS = [("New Bedford", "02740"), ("New Bedford", "02745"), ("Dartmouth", "02747"),
         ("Dartmouth", "02748"), ("Fall River", "02720"), ("Fairhaven", "02719"),
         ("Westport", "02790"), ("Somerset", "02726"), ("Mattapoisett", "02739"),
         ("Acushnet", "02743"), ("Lakeville", "02347"), ("Tiverton", "02878")]
PAY = ["check", "venmo", "venmo", "cash", "cash app", "cashapp", "check", "venmo"]


def customers(count=140):
    people = []
    for _ in range(count):
        name = f"{R.choice(FIRST)} {R.choice(LAST)}"
        if R.random() < 0.08:
            name = f"{R.choice(FIRST)} & {R.choice(FIRST)} {R.choice(LAST)}"
        if R.random() < 0.04:
            name = R.choice(FIRST)
        town, zipc = R.choice(TOWNS)
        state = "RI" if town == "Tiverton" else "MA"
        number = str(R.randint(2, 980))
        street = R.choice(STREETS)
        roll = R.random()
        if roll < 0.06:
            line = f"??? {street}"
        elif roll < 0.10:
            line = street
        elif roll < 0.12:
            line = f"P.O. Box {R.randint(10, 400)}"
        elif roll < 0.15:
            line = ""
        else:
            line = f"{number} {street}"
        city = f"{town}, {state} {zipc}" if R.random() > 0.12 else f"{town}, {state}"
        people.append((name, line, city))
    return people


def exact_rows(jobs):
    """Exactly `jobs` rows, spread over the year so far. About four in five
    customers appear once; the rest come back."""
    people = customers(int(jobs * 0.8))
    first, last = dt.date(2026, 1, 5), dt.date(2026, 10, 19)
    days = sorted(first + dt.timedelta(days=R.randint(0, (last - first).days)) for _ in range(jobs))
    out, used = [], []
    for day in days:
        if used and R.random() < 0.2:
            name, line, city = R.choice(used)
        else:
            name, line, city = people[len(used) % len(people)]
            used.append((name, line, city))
        price = R.choice([50, 75, 100, 150, 200, 250, 300, 350, 400, 450, 500, 600, 800, 1200])
        red = R.random() < 0.06
        pay = "" if red or R.random() < 0.05 else R.choice(PAY)
        check = str(R.randint(100, 9999)) if pay == "check" else ""
        not_mailing = "XXX" if R.random() < 0.03 else ""
        out.append((day, name, line, city, price, red, pay, check, not_mailing))
    return out


def rows():
    if JOBS:
        return exact_rows(JOBS)
    people = customers()
    day = dt.date(2026, 1, 5)
    out = []
    while day < dt.date(2026, 10, 20):
        for _ in range(R.choice([0, 1, 2, 3, 4])):
            name, line, city = R.choice(people)
            price = R.choice([50, 75, 100, 150, 200, 250, 300, 350, 400, 450, 500, 600, 800, 1200])
            red = R.random() < 0.06
            pay = "" if red or R.random() < 0.05 else R.choice(PAY)
            check = str(R.randint(100, 9999)) if pay == "check" else ""
            not_mailing = "XXX" if R.random() < 0.03 else ""
            out.append((day, name, line, city, price, red, pay, check, not_mailing))
        day += dt.timedelta(days=1)
    return out


def serial(d):
    return (d - dt.date(1899, 12, 30)).days


def main():
    strings, index = [], {}

    def s(text):
        if text not in index:
            index[text] = len(strings)
            strings.append(text)
        return index[text]

    def cell(ref, value=None, style=0, text=None):
        st = f' s="{style}"' if style else ""
        if text is not None:
            return f'<c r="{ref}" t="s"{st}><v>{s(text)}</v></c>'
        return f'<c r="{ref}"{st}><v>{value}</v></c>'

    headers = ["Date", "Customer Name", "# and Street Name", "City, State & Zip", "Price",
               "Form of Payment", "Check #", "Not Mailing Address"]
    xml_rows = ['<row r="1">' + "".join(cell(f"{chr(66 + i)}1", text=h, style=1) for i, h in enumerate(headers)) + "</row>"]
    for n, (day, name, line, city, price, red, pay, check, nm) in enumerate(rows(), start=2):
        parts = [cell(f"B{n}", serial(day), style=3 if n == 2 else 2)]
        if name:
            parts.append(cell(f"C{n}", text=name))
        if line:
            parts.append(cell(f"D{n}", text=line))
        if city:
            parts.append(cell(f"E{n}", text=city))
        parts.append(cell(f"F{n}", price, style=4 if red else 0))
        if pay:
            parts.append(cell(f"G{n}", text=pay))
        if check:
            parts.append(cell(f"H{n}", int(check)))
        if nm:
            parts.append(cell(f"I{n}", text=nm))
        xml_rows.append(f'<row r="{n}">' + "".join(parts) + "</row>")

    ns = 'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'
    rel = 'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
    sheet1 = f'<?xml version="1.0" encoding="UTF-8"?><worksheet {ns}><sheetData>{"".join(xml_rows)}</sheetData></worksheet>'
    sheet2 = f'<?xml version="1.0" encoding="UTF-8"?><worksheet {ns}><sheetData/></worksheet>'
    shared = (f'<?xml version="1.0" encoding="UTF-8"?><sst {ns} count="{len(strings)}" uniqueCount="{len(strings)}">'
              + "".join(f"<si><t>{escape(t)}</t></si>" for t in strings) + "</sst>")
    styles = f'''<?xml version="1.0" encoding="UTF-8"?><styleSheet {ns}>
<numFmts count="2"><numFmt numFmtId="164" formatCode="m/d"/><numFmt numFmtId="165" formatCode="m/d/yyyy"/></numFmts>
<fonts count="2"><font><sz val="10"/><name val="Arial"/></font><font><b/><sz val="10"/><name val="Arial"/></font></fonts>
<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FFFF0000"/><bgColor indexed="64"/></patternFill></fill></fills>
<borders count="1"><border/></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="5"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" applyFont="1"/>
<xf numFmtId="164" fontId="0" fillId="0" borderId="0" applyNumberFormat="1"/><xf numFmtId="165" fontId="0" fillId="0" borderId="0" applyNumberFormat="1"/>
<xf numFmtId="0" fontId="0" fillId="2" borderId="0" applyFill="1"/></cellXfs></styleSheet>'''
    workbook = (f'<?xml version="1.0" encoding="UTF-8"?><workbook {ns} {rel}><sheets>'
                '<sheet name="Client Job List" sheetId="1" r:id="rId1"/><sheet name="Contracted Labor" sheetId="2" r:id="rId2"/>'
                "</sheets></workbook>")
    wb_rels = ('<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
               '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
               '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>'
               '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>'
               '<Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
               "</Relationships>")
    root_rels = ('<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                 '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
                 "</Relationships>")
    types = ('<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
             '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
             '<Default Extension="xml" ContentType="application/xml"/>'
             '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
             '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
             '<Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
             '<Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>'
             '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
             "</Types>")
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", types)
        z.writestr("_rels/.rels", root_rels)
        z.writestr("xl/workbook.xml", workbook)
        z.writestr("xl/_rels/workbook.xml.rels", wb_rels)
        z.writestr("xl/worksheets/sheet1.xml", sheet1)
        z.writestr("xl/worksheets/sheet2.xml", sheet2)
        z.writestr("xl/sharedStrings.xml", shared)
        z.writestr("xl/styles.xml", styles)
    print(f"{len(xml_rows) - 1} job rows written to {os.path.basename(OUT)}")


if __name__ == "__main__":
    main()
