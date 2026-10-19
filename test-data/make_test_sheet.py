"""Builds "Ace test sheet (fake data).xlsx" and README.md in this folder.

A stand-in for Ashley's own spreadsheet, for trying the Excel import (build
step 7) without her real file. The layout is a guess: her column headings are
not known yet. Every name, phone number and house number is made up; phone
numbers use the 555-0100 to 555-0199 range set aside for fiction.

Seeded, so it comes out the same every run. Needs openpyxl.
Run: python3 test-data/make_test_sheet.py
"""

import datetime as dt
import os
import random

from openpyxl import Workbook, load_workbook
from openpyxl.styles import Alignment, Font, PatternFill

R = random.Random(20261019)
HERE = os.path.dirname(os.path.abspath(__file__))
XLSX_NAME = "Ace test sheet (fake data).xlsx"
XLSX = os.path.join(HERE, XLSX_NAME)
README = os.path.join(HERE, "README.md")
TODAY = dt.date(2026, 10, 19)

FIRST = ["Linda", "Mark", "Dave", "Karen", "Paul", "Maria", "Joe", "Susan", "Mike", "Donna",
         "Steve", "Patty", "Kevin", "Lisa", "Brian", "Tina", "Rich", "Carol", "Jim", "Nancy",
         "Tony", "Diane", "Ed", "Janet", "Bob", "Kathy", "Chris", "Michelle", "Dan", "Sharon",
         "Manny", "Fatima", "Tom", "Rose", "Sean", "Ana", "Greg", "Beth", "Al", "Joanne",
         "Ray", "Denise", "Frank", "Lori", "Matt", "Helen", "Nick", "Amy", "Luis", "Cheryl"]
LAST = ["Silva", "Pereira", "Medeiros", "Souza", "Costa", "Rego", "Furtado", "Almeida",
        "Sullivan", "Murphy", "Kelly", "O'Brien", "Walsh", "Doherty", "Gallagher", "Callahan",
        "Nguyen", "Tran", "Johnson", "Smith", "Brown", "Miller", "Davis", "Wilson", "Moore",
        "Taylor", "Anderson", "Thomas", "Jackson", "White", "Harris", "Martin", "Thompson",
        "Garcia", "Lopez", "Ramos", "Cabral", "Amaral", "Moniz", "Botelho", "Raposo", "Tavares",
        "Fontaine", "Thibodeau", "Gagnon", "Leblanc", "Pelletier", "Ouellette", "Macomber",
        "Keane", "Pratt", "Hathaway", "Howland", "Sampson", "Bassett", "Leonard", "Crowell"]
STREETS = [("Elm", "St"), ("Main", "St"), ("Bay", "Rd"), ("Plymouth", "St"), ("County", "St"),
           ("Pleasant", "St"), ("Highland", "Ave"), ("Prospect", "St"), ("Cedar", "St"),
           ("Oak", "St"), ("Maple", "Ave"), ("Winthrop", "St"), ("Broadway", ""), ("Center", "St"),
           ("Purchase", "St"), ("Somerset", "Ave"), ("Bedford", "St"), ("Precinct", "St"),
           ("Summer", "St"), ("Union", "St"), ("Chestnut", "St"), ("Pine", "St"),
           ("Taunton", "Ave"), ("Middleboro", "Ave"), ("Locust", "St"), ("Myricks", "St"),
           ("Center", "Ave"), ("Walnut", "St"), ("Bridge", "St"), ("Water", "St")]
SUFFIX_ALT = {"St": ["St", "Street", "st", "St."], "Rd": ["Rd", "Road", "rd"],
              "Ave": ["Ave", "Avenue", "ave"], "": [""]}
TOWNS = ["Taunton", "Raynham", "Middleborough", "Bridgewater", "Lakeville", "Easton", "Norton",
         "Dighton", "Berkley", "Freetown", "Rehoboth", "Brockton", "Fall River", "New Bedford",
         "Dartmouth", "Somerset", "Swansea", "Seekonk"]
TOWN_ALT = {"Middleborough": "Middleboro", "Bridgewater": "Bridgewtr", "New Bedford": "NB",
            "Fall River": "FR", "Taunton": "taunton", "Dartmouth": "N. Dartmouth"}
BUSINESSES = [("Cobblestone Realty Group", "Dave"), ("Bayberry Property Mgmt", "Ana"),
              ("Kettle Pond Builders", "Rich"), ("Granite Ledge Homes", "Kathy"),
              ("Whippoorwill Rentals", "Tom"), ("Cedar Swamp Realty", "Michelle"),
              ("Three Rivers Property Co", "Manny"), ("Quarry Hill Apartments", "Sharon"),
              ("Silver Lake Condo Assn", "Greg"), ("Fox Run Estates", "Lori"),
              ("Old Mill Contracting", "Sean"), ("Herring Run Storage", "Al")]
AREA = ["508", "774", "781", "617", "401", "339", "857", "978", "413", "351"]

JOB_TEXT = {
    "junk": ["garage cleanout", "basement cleanout", "attic", "junk removal", "furniture",
             "couch + chair", "appliances", "fridge + washer", "estate cleanout",
             "hot tub removal", "shed cleanout", "mattress x2", "yard debris", "office cleanout",
             "full house", "piano", "tv + dresser", "brush pile", "Garage", "basement"],
    "demo": ["demo shed", "deck removal", "demo - kitchen", "above ground pool removal",
             "fence removal", "demo bathroom", "tear out carpet", "DEMO"],
    "dumpster": ["15yd dumpster", "dumpster drop", "dumpster #{n} drop", "drop 15 yd",
                 "dumpster pickup", "pick up dumpster #{n}", "swap dumpster", "10yd dumpster",
                 "dumpster"],
    "estimate": ["estimate", "est - basement", "look at garage for price", "quote visit"],
    "other": ["call back", "brush pickup?", "misc", "see notes"],
}
NOTES = ["gate code 4412", "dog in yard", "call b4", "2nd floor walkup", "back of house",
         "dump fee 85", "referral from Cobblestone", "repeat cust", "left in driveway",
         "9am", "after 2pm", "tenant there, landlord pays", "text don't call", "heavy - 2 guys",
         "extra $50 mattress", "rescheduled from last wk", "nice lady", "steep driveway",
         "senior discount", "parking on street only"]
MONTHS = ["JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE", "JULY", "AUGUST",
          "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER"]
MONTH_WEIGHT = [3, 3, 5, 7, 9, 10, 10, 10, 9, 8, 6, 4]
MON_ABBR = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


def pick(seq):
    return R.choice(seq)


# ---------- The made-up customers ----------

phone_pool = [(a, n) for a in AREA for n in range(100, 200)]
R.shuffle(phone_pool)


def next_phone():
    return phone_pool.pop()


def make_customers():
    people, seen = [], set()
    while len(people) < 900:
        first, last = pick(FIRST), pick(LAST)
        if (first, last) in seen:
            continue
        seen.add((first, last))
        street, suffix = pick(STREETS)
        r = R.random()
        weight = 1 if r < 0.9 else (2 if r < 0.98 else 4)
        people.append({"id": len(people), "first": first, "last": last, "business": None,
                       "phone": next_phone(), "number": R.randint(1, 420), "street": street,
                       "suffix": suffix, "town": pick(TOWNS), "weight": weight})
    for name, contact in BUSINESSES:
        street, suffix = pick(STREETS)
        people.append({"id": len(people), "first": contact, "last": "", "business": name,
                       "phone": next_phone(), "number": R.randint(1, 420), "street": street,
                       "suffix": suffix, "town": pick(TOWNS), "weight": 6})
    return people


CUSTOMERS = make_customers()
WEIGHTS = [c["weight"] for c in CUSTOMERS]


# ---------- The jobs (the truth behind each row) ----------

def random_date(year, last_day):
    while True:
        month = R.choices(range(1, 13), weights=MONTH_WEIGHT)[0]
        day = R.randint(1, 31)
        try:
            d = dt.date(year, month, day)
        except ValueError:
            continue
        if d.weekday() == 6 or d > last_day:  # no Sundays
            continue
        return d


def make_jobs(year, count, last_day):
    jobs = []
    for _ in range(count):
        cust = R.choices(CUSTOMERS, weights=WEIGHTS)[0]
        kind = R.choices(["junk", "dumpster", "demo", "estimate", "other"],
                         weights=[62, 20, 8, 6, 4])[0]
        if kind == "junk":
            price = R.randrange(150, 1225, 25)
        elif kind == "demo":
            price = R.randrange(400, 3550, 50)
        elif kind == "dumpster":
            price = R.randrange(350, 675, 25)
        elif kind == "other":
            price = R.choice([None, 100, 150])
        else:
            price = None
        d = random_date(year, last_day)
        future = d > TODAY
        paid = (not future) and price is not None and R.random() < 0.86
        jobs.append({"cust": cust, "kind": kind, "price": price, "date": d, "paid": paid,
                     "pay": R.choices(["cash", "check", "card"], weights=[45, 30, 25])[0],
                     "cancelled": R.random() < 0.015})
    jobs.sort(key=lambda j: j["date"])
    # A few rows entered late, so they sit out of date order.
    for _ in range(max(1, count // 50)):
        i = R.randrange(len(jobs) - 1)
        jobs[i], jobs[i + 1] = jobs[i + 1], jobs[i]
    return jobs


# ---------- How a person in an office would have typed each cell ----------

def typo(word):
    if len(word) < 5:
        return word
    i = R.randrange(1, len(word) - 2)
    return word[:i] + word[i + 1] + word[i] + word[i + 2:]


def render_name(c, truth):
    if c["business"]:
        r = R.random()
        if r < 0.7:
            return c["business"]
        return "%s (%s)" % (c["business"], c["first"]) if r < 0.85 else "%s - %s" % (c["business"], c["first"])
    full = "%s %s" % (c["first"], c["last"])
    r = R.random()
    if r < 0.68:
        return full
    if r < 0.78:
        return "%s, %s" % (c["last"], c["first"])
    if r < 0.83:
        return full.upper()
    if r < 0.88:
        truth["name_partial"] = True
        return pick(["Mrs. %s", "Mr. %s", "%s"]) % c["last"]
    if r < 0.93:
        return full + " "
    truth["name_typo"] = True
    return "%s %s" % (c["first"], typo(c["last"]))


def fmt_phone(p):
    return "%s-555-0%d" % (p[0], p[1])


def render_phone(c, truth):
    a, n = c["phone"]
    r = R.random()
    if r < 0.45:
        return fmt_phone(c["phone"])
    if r < 0.60:
        return "(%s) 555-0%d" % (a, n)
    if r < 0.68:
        return "%s.555.0%d" % (a, n)
    if r < 0.78:
        return int("%s5550%d" % (a, n))  # typed as a number, so Excel stores digits only
    if r < 0.82:
        truth["no_area_code"] = True
        return "555-0%d" % n
    if r < 0.85:
        truth["two_numbers"] = True
        return "%s / %s" % (fmt_phone(c["phone"]), fmt_phone(next_phone()))
    if r < 0.86:
        return fmt_phone(c["phone"]) + " x2"
    truth["no_phone"] = True
    return None


def street_text(c):
    suffix = pick(SUFFIX_ALT[c["suffix"]])
    return ("%s %s" % (c["street"], suffix)).strip()


def render_address_2026(c, truth, seen_before):
    r = R.random()
    if r < 0.03:
        truth["no_house_number"] = True
        return street_text(c)
    if r < 0.06 and seen_before:
        truth["address_same"] = True
        return "same"
    if r < 0.08:
        return "%d %s, %s" % (c["number"], street_text(c), c["town"])
    if r < 0.10:
        return ("%d %s" % (c["number"], street_text(c))).lower()
    return "%d %s" % (c["number"], street_text(c))


def render_town_2026(c, truth):
    r = R.random()
    if r < 0.05:
        truth["no_town"] = True
        return None
    if r < 0.10 and c["town"] in TOWN_ALT:
        return TOWN_ALT[c["town"]]
    return c["town"]


def render_address_2025(c, truth):
    street = "%d %s" % (c["number"], street_text(c))
    r = R.random()
    if r < 0.03:
        truth["no_house_number"] = True
        return "%s, %s" % (street_text(c), c["town"])
    if r < 0.08:
        truth["no_town"] = True
        return street
    if r < 0.55:
        return "%s, %s" % (street, c["town"])
    if r < 0.85:
        return "%s %s MA" % (street, c["town"])
    return "%s, %s, MA" % (street, TOWN_ALT.get(c["town"], c["town"]))


def render_job(job):
    return pick(JOB_TEXT[job["kind"]]).replace("{n}", str(R.randint(1, 6)))


def render_price(job, truth):
    p = job["price"]
    if p is None:
        truth["no_price"] = True
        return R.choice([None, None, None, "tbd", "quote"]), None
    r = R.random()
    if r < 0.58:
        return p, ('"$"#,##0' if R.random() < 0.5 else None)
    if r < 0.73:
        return "${:,}".format(p), None
    if r < 0.77:
        return "%d.00" % p, None
    if r < 0.80:
        return "%d+50" % (p - 50), None
    if r < 0.82 and not job["paid"]:
        return "quote %d" % p, None
    if r < 0.84:
        return "%d %s" % (p, job["pay"]), None
    if r < 0.93:
        return float(p), "#,##0.00"
    truth["no_price"] = True
    return None, None


PAID_TEXT = {
    "cash": ["cash", "Cash", "CASH", "pd cash", "pd cash {p}", "paid cash", "C"],
    "check": ["chk", "check", "Check", "ck #{ck}", "chk {ck}", "pd chk"],
    "card": ["card", "CC", "cc", "visa", "pd card", "sq", "credit card"],
}


def render_paid(job, truth, yes_no):
    """Returns (paid cell, extra note)."""
    p = job["price"] or 0
    if job["cancelled"]:
        return R.choice([None, "cxl"]), None
    if job["date"] > TODAY or job["price"] is None:
        return None, None  # not done yet, or nothing to pay
    if not job["paid"]:
        if yes_no and R.random() < 0.2:
            return "n", None
        return R.choice([None, None, None, "owes", "no", "OWES %d" % p, "inv sent", "unpaid"]), None
    r = R.random()
    if r < 0.02:
        truth["unsupported_payment"] = True
        return R.choice(["venmo", "zelle"]), None
    if r < 0.04 and p > 150:
        truth["partial"] = True
        return "pd %d cash owes 100" % (p - 100), None
    if r < 0.06 and job["pay"] == "cash":
        return None, "pd cash %d" % p  # the payment written in Notes instead
    if yes_no and r < 0.25:
        return R.choice(["y", "Y", "yes"]), None
    return pick(PAID_TEXT[job["pay"]]).format(p=p, ck=R.randint(1001, 1999)), None


def render_date(d, truth, long_year):
    r = R.random()
    if r < 0.92:
        return d, ("m/d/yyyy" if long_year else "m/d/yy")
    truth["text_date"] = True
    if r < 0.96:
        return "%d/%d" % (d.month, d.day), None
    if r < 0.985:
        return "%s %d" % (MON_ABBR[d.month - 1], d.day), None
    if r < 0.99:
        return "%d/%d/%02d" % (d.month, d.day, d.year % 100), None
    truth["date_unknown"] = True
    return "TBD", None


def render_notes(job, extra):
    parts = []
    if job["cancelled"]:
        parts.append(R.choice(["CANCELLED", "cxl - customer called", "cancelled, rebook?"]))
    if extra:
        parts.append(extra)
    if R.random() < 0.45:
        parts.append(pick(NOTES))
    if job["kind"] == "dumpster" and R.random() < 0.3:
        parts.append("%.1f tons" % R.choice([1.6, 1.9, 2.0, 2.2, 2.4, 2.8, 3.1]))
    return ", ".join(parts) or None


# ---------- Writing the workbook ----------

FONT = "Calibri"
BOLD = Font(name=FONT, bold=True)
PLAIN = Font(name=FONT)
STRIKE = Font(name=FONT, strike=True)
UNPAID_FILL = PatternFill("solid", fgColor="FFF2CC")
MONTH_FILL = PatternFill("solid", fgColor="D9D9D9")


def put(ws, row, col, value, number_format=None, font=PLAIN):
    cell = ws.cell(row=row, column=col, value=value)
    cell.font = font
    if number_format:
        cell.number_format = number_format
    return cell


def write_tab_2026(ws, jobs):
    headers = ["Date", "Customer", "Phone", "Address", "Town", "Job", "Price", "Paid", "Notes"]
    put(ws, 1, 1, "ACE JUNK REMOVAL - 2026 JOBS", font=Font(name=FONT, bold=True, size=14))
    for i, h in enumerate(headers, 1):
        put(ws, 3, i, h, font=BOLD)
    ws.freeze_panes = "A4"
    rows, row, month, seen, dup_at = [], 4, None, set(), set(R.sample(range(len(jobs)), 4))
    for idx, job in enumerate(jobs):
        if job["date"].month != month:
            month = job["date"].month
            put(ws, row, 1, MONTHS[month - 1], font=BOLD)
            for col in range(1, 10):
                ws.cell(row=row, column=col).fill = MONTH_FILL
            ws.merge_cells(start_row=row, start_column=1, end_row=row, end_column=9)
            rows.append({"kind": "month"})
            row += 1
        c, truth = job["cust"], {"kind": "job", "cust": c_id(job), "cancelled": job["cancelled"]}
        date, date_fmt = render_date(job["date"], truth, long_year=False)
        price, price_fmt = render_price(job, truth)
        paid, extra = render_paid(job, truth, yes_no=False)
        values = [(date, date_fmt), (render_name(c, truth), None), (render_phone(c, truth), None),
                  (render_address_2026(c, truth, c["id"] in seen), None),
                  (render_town_2026(c, truth), None), (render_job(job), None),
                  (price, price_fmt), (paid, None), (render_notes(job, extra), None)]
        seen.add(c["id"])
        copies = 2 if idx in dup_at else 1
        for copy in range(copies):
            font = STRIKE if job["cancelled"] else PLAIN
            for col, (v, f) in enumerate(values, 1):
                cell = put(ws, row, col, v, f, font)
                if not job["paid"] and not job["cancelled"] and job["date"] <= TODAY and job["price"]:
                    cell.fill = UNPAID_FILL
            entry = dict(truth)
            if copy:
                entry["duplicate"] = True
            rows.append(entry)
            row += 1
        if R.random() < 0.01:
            rows.append({"kind": "blank"})
            row += 1
    total = sum(v for r in ws.iter_rows(min_row=4, max_row=row - 1, min_col=7, max_col=7)
                for v in [r[0].value] if isinstance(v, (int, float)))
    row += 1  # a blank row before the total
    rows.append({"kind": "blank"})
    put(ws, row, 2, "TOTAL", font=BOLD)
    put(ws, row, 7, total, '"$"#,##0', BOLD)
    rows.append({"kind": "total"})
    widths = [10, 26, 16, 26, 14, 24, 10, 16, 34]
    for i, w in enumerate(widths):
        ws.column_dimensions["ABCDEFGHI"[i]].width = w
    return rows, total


def write_tab_2025(ws, jobs):
    headers = ["Date", "Name", "Phone #", "Address", "Job Description", "$", "Pd?", "Notes"]
    for i, h in enumerate(headers, 1):
        put(ws, 1, i, h, font=BOLD)
    ws.freeze_panes = "A2"
    rows, row, dup_at = [], 2, set(R.sample(range(len(jobs)), 3))
    for idx, job in enumerate(jobs):
        c, truth = job["cust"], {"kind": "job", "cust": c_id(job), "cancelled": job["cancelled"]}
        date, date_fmt = render_date(job["date"], truth, long_year=True)
        price, price_fmt = render_price(job, truth)
        paid, extra = render_paid(job, truth, yes_no=True)
        values = [(date, date_fmt), (render_name(c, truth), None), (render_phone(c, truth), None),
                  (render_address_2025(c, truth), None), (render_job(job), None),
                  (price, price_fmt), (paid, None), (render_notes(job, extra), None)]
        for copy in range(2 if idx in dup_at else 1):
            for col, (v, f) in enumerate(values, 1):
                put(ws, row, col, v, f, STRIKE if job["cancelled"] else PLAIN)
            entry = dict(truth)
            if copy:
                entry["duplicate"] = True
            rows.append(entry)
            row += 1
        if R.random() < 0.01:
            rows.append({"kind": "blank"})
            row += 1
    ws.auto_filter.ref = "A1:H%d" % (row - 1)
    widths = [11, 26, 16, 34, 24, 9, 12, 34]
    for i, w in enumerate(widths):
        ws.column_dimensions["ABCDEFGH"[i]].width = w
    return rows


def c_id(job):
    return job["cust"]["id"]


def write_dumpsters(ws):
    headers = ["#", "Size", "Where", "Dropped", "Due back", "Agreed (tons)", "Price", "Notes"]
    for i, h in enumerate(headers, 1):
        put(ws, 1, i, h, font=BOLD)
    out = R.sample([c for c in CUSTOMERS if not c["business"]], 4)
    rows = [
        (1, "15 yd", "%s %s - %d %s" % (out[0]["first"], out[0]["last"], out[0]["number"], street_text(out[0])),
         dt.date(2026, 10, 10), dt.date(2026, 10, 17), 2, 450, "OVERDUE call"),
        (2, "15 yd", "yard", None, None, None, None, "cracked door - dont send"),
        (3, "15 yd", "%s - %s" % (out[1]["last"], out[1]["town"]), dt.date(2026, 10, 14),
         dt.date(2026, 10, 21), 2, 450, None),
        (4, "10 yd", "YARD", None, None, None, None, None),
        (5, "15 yd", "%d %s %s" % (out[2]["number"], street_text(out[2]), out[2]["town"]),
         dt.date(2026, 10, 16), "next fri", "2 tons", "$475", "contractor"),
        (6, "10 yd", "out - %s %s" % (out[3]["first"], out[3]["last"]), "10/18", dt.date(2026, 10, 25),
         1.5, 375, None),
    ]
    for r, values in enumerate(rows, 2):
        for col, v in enumerate(values, 1):
            put(ws, r, col, v, "m/d/yy" if isinstance(v, dt.date) else None)
    for i, w in enumerate([5, 7, 40, 10, 10, 13, 8, 26]):
        ws.column_dimensions["ABCDEFGH"[i]].width = w


def summarize(rows):
    jobs = [r for r in rows if r["kind"] == "job"]
    count = lambda key: sum(1 for r in jobs if r.get(key))
    return {
        "job rows (including duplicates)": len(jobs),
        "exact duplicate rows": count("duplicate"),
        "blank rows": sum(1 for r in rows if r["kind"] == "blank"),
        "month heading rows": sum(1 for r in rows if r["kind"] == "month"),
        "total rows": sum(1 for r in rows if r["kind"] == "total"),
        "cancelled jobs": count("cancelled"),
        "rows with no phone number": count("no_phone"),
        "rows with a phone missing its area code": count("no_area_code"),
        "rows with two phone numbers": count("two_numbers"),
        "rows with a date typed as text": count("text_date"),
        "rows dated TBD": count("date_unknown"),
        "rows with no price": count("no_price"),
        "rows with venmo or zelle": count("unsupported_payment"),
        "rows with part paid, part owed": count("partial"),
        "rows with no house number": count("no_house_number"),
        "rows with no town": count("no_town"),
        "rows where address is \"same\"": count("address_same"),
        "rows with a misspelled last name": count("name_typo"),
        "rows with a last name only": count("name_partial"),
        "different real customers": len({r["cust"] for r in jobs}),
    }


def check(path, key26, key25):
    """Reads the file back and recounts a few things straight from the cells."""
    wb = load_workbook(path)
    ws = wb["2026"]
    merged = {r.min_row for r in ws.merged_cells.ranges}
    job_rows = [r for r in range(4, ws.max_row + 1)
                if r not in merged and ws.cell(r, 2).value not in (None, "TOTAL")]
    assert len(job_rows) == key26["job rows (including duplicates)"], "2026 job rows"
    assert sum(1 for r in job_rows if ws.cell(r, 3).value is None) == key26["rows with no phone number"]
    assert len(merged) == key26["month heading rows"]
    ws = wb["2025"]
    job_rows = [r for r in range(2, ws.max_row + 1) if ws.cell(r, 2).value is not None]
    assert len(job_rows) == key25["job rows (including duplicates)"], "2025 job rows"
    assert sum(1 for r in job_rows if ws.cell(r, 3).value is None) == key25["rows with no phone number"]
    assert wb.sheetnames == ["2026", "2025", "Dumpsters"]


def main():
    jobs25 = make_jobs(2025, 610, dt.date(2025, 12, 31))
    jobs26 = make_jobs(2026, 450, dt.date(2026, 10, 30))
    wb = Workbook()
    ws26 = wb.active
    ws26.title = "2026"
    rows26, total26 = write_tab_2026(ws26, jobs26)
    rows25 = write_tab_2025(wb.create_sheet("2025"), jobs25)
    write_dumpsters(wb.create_sheet("Dumpsters"))
    wb.save(XLSX)

    key26, key25 = summarize(rows26), summarize(rows25)
    check(XLSX, key26, key25)
    both = {r["cust"] for r in rows26 if r["kind"] == "job"} & {r["cust"] for r in rows25 if r["kind"] == "job"}
    every = {r["cust"] for r in rows26 + rows25 if r["kind"] == "job"}
    write_readme(key26, key25, total26, len(every), len(both))
    print("Wrote", XLSX)
    print("2026:", key26)
    print("2025:", key25)
    print("Different customers across both years:", len(every), "in both years:", len(both))


def write_readme(key26, key25, total26, every, both):
    lines = [
        "# Test spreadsheet (fake data)",
        "",
        "`%s` stands in for Ashley's own spreadsheet, so the Excel import (build" % XLSX_NAME,
        "step 7, Mac only) can be tried as often as needed without her real file.",
        "",
        "- **Everything in it is made up.** Names are random pairings, house numbers are",
        "  invented on common street names in real South Coast towns, and every phone",
        "  number is in the 555-0100 to 555-0199 range set aside for fiction. The",
        "  repository is public: never put Ashley's real file, or anything copied from",
        "  it, in here.",
        "- **The layout is a guess** (Kyle, 2026-10-19: \"reasonable test for now\").",
        "  Ashley's real column headings are not known yet. When they are, change",
        "  `make_test_sheet.py` to match and run it again.",
        "- Rebuild it: `python3 test-data/make_test_sheet.py` (needs openpyxl). It",
        "  comes out the same every time, and rewrites this README with the counts.",
        "",
        "## What is in it",
        "",
        "Three tabs, the way a small office's workbook tends to grow:",
        "",
        "| Tab | Layout |",
        "|---|---|",
        "| `2026` | A title in row 1, a blank row, headings in row 3: Date, Customer, Phone, Address, Town, Job, Price, Paid, Notes. A grey merged row starts each month. Unpaid past jobs are shaded yellow (the colour is the only sign). Cancelled jobs are struck through. A TOTAL row at the bottom. |",
        "| `2025` | Headings in row 1, worded differently: Date, Name, Phone #, Address, Job Description, $, Pd?, Notes. The town is part of the address. A filter is on. |",
        "| `Dumpsters` | Six dumpsters and where they are. Not customers or jobs; an import should leave it alone or ask. |",
        "",
        "## The mess it holds on purpose",
        "",
        "- **Names:** \"Linda Johnson\", \"Johnson, Linda\", \"LINDA JOHNSON\", \"Mrs. Johnson\",",
        "  trailing spaces, a swapped-letter misspelling, and businesses written as",
        "  \"Cobblestone Realty Group (Dave)\". The same person is often written",
        "  several ways across rows.",
        "- **Phones:** 508-555-0123, (508) 555-0123, 508.555.0123, digits stored as a",
        "  number, no area code, two numbers in one cell, an \"x2\" extension, blank.",
        "- **Addresses:** street abbreviations that vary, the town in the address",
        "  column, no house number, \"same\" (meaning same as last time), lower case,",
        "  town nicknames (Middleboro, NB, FR).",
        "- **Prices:** numbers, \"$1,200\" typed as text, \"300.00\", \"350+50\",",
        "  \"quote 800\", \"300 cash\", \"tbd\", blank.",
        "- **Paid:** \"pd cash 300\", \"cash\", \"chk 1043\", \"ck #1043\", \"CC\", \"sq\",",
        "  \"visa\", \"owes\", \"OWES 300\", \"inv sent\", \"pd 200 cash owes 100\", \"y\" / \"n\"",
        "  on the 2025 tab, blank, and venmo or zelle (not one of the app's cash,",
        "  check or card). Sometimes the payment is written in Notes instead.",
        "- **Dates:** real dates, plus \"10/3\", \"Oct 3\", \"10/3/26\" typed as text, and",
        "  \"TBD\". A few rows are out of date order (entered late).",
        "- **Rows that are not jobs:** month headings, blank rows, the TOTAL row, and",
        "  rows entered twice.",
        "",
        "## Answer key (what the import should find)",
        "",
        "Counted by the script from the made-up records, then checked against the file.",
        "",
        "| | 2026 tab | 2025 tab |",
        "|---|---|---|",
    ]
    for k in key26:
        lines.append("| %s | %s | %s |" % (k, key26[k], key25[k]))
    lines += [
        "",
        "- Different real customers across both tabs: **%d**, of whom %d appear in both" % (every, both),
        "  years. Some of them can't be told apart from the cells alone (a misspelled",
        "  name with no phone, for example), so a good import gets close to this number",
        "  and asks about the rest, rather than matching it exactly.",
        "- The 2026 TOTAL row reads $%s: the sum of the prices that are real numbers," % "{:,}".format(int(total26)),
        "  typed in as a value (not a formula), so it reads the same in any program.",
        "  Prices typed as text are not in it.",
        "",
    ]
    with open(README, "w") as f:
        f.write("\n".join(lines))


if __name__ == "__main__":
    main()
