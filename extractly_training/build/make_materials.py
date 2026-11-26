"""Generate the FICTIONAL training source documents (PDFs) and companion Excel workbooks
for the Melo LLP Caseware Extractly training session.

All names, amounts and documents are fictional and created solely for training.
"""
import os, random
from reportlab.lib.pagesizes import letter
from reportlab.pdfgen import canvas
from reportlab.lib import colors
from reportlab.lib.units import inch
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.worksheet.datavalidation import DataValidation

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAT = os.path.join(ROOT, "materials")
os.makedirs(MAT, exist_ok=True)

NAVY = colors.HexColor("#14284B")
GREEN = colors.HexColor("#2E7D4F")
GREY = colors.HexColor("#5F6B7A")
LIGHT = colors.HexColor("#EEF1F5")

WATERMARK = "FICTIONAL SAMPLE - FOR TRAINING USE ONLY"


def watermark(c, w, h):
    c.saveState()
    c.setFillColor(colors.HexColor("#C0392B"))
    c.setFont("Helvetica-Bold", 8)
    c.drawCentredString(w / 2, 0.35 * inch, WATERMARK + "  |  Melo LLP Extractly Training 2026")
    c.restoreState()


def money(v):
    return f"(${abs(v):,.2f})" if v < 0 else f"${v:,.2f}"


# --------------------------------------------------------------------------------------
# DEMO 1 - Equipment lease agreement
# --------------------------------------------------------------------------------------
r = 0.065 / 12
N = 60
COST = 116000.00
DOWN = 18000.00
FIN = COST - DOWN
PMT = round(FIN * r / (1 - (1 + r) ** -N), 2)  # 1,917.48
PMT_HST = round(PMT * 0.13, 2)
DOWN_HST = round(DOWN * 0.13, 2)


def demo1_pdf(path):
    w, h = letter
    c = canvas.Canvas(path, pagesize=letter)
    c.setTitle("Equipment Lease Agreement - FICTIONAL")
    c.setFillColor(NAVY)
    c.setFont("Helvetica-Bold", 18)
    c.drawString(0.9 * inch, h - 1.0 * inch, "Northbridge Equipment Finance Inc.")
    c.setFont("Helvetica", 9)
    c.setFillColor(GREY)
    c.drawString(0.9 * inch, h - 1.22 * inch, "450 Harbourview Road, Suite 1200, Toronto, Ontario  M5X 0A0   |   HST Reg. No. 81234 5678 RT0001")
    c.setStrokeColor(NAVY); c.setLineWidth(1.2)
    c.line(0.9 * inch, h - 1.35 * inch, w - 0.9 * inch, h - 1.35 * inch)

    c.setFillColor(colors.black)
    c.setFont("Helvetica-Bold", 15)
    c.drawString(0.9 * inch, h - 1.8 * inch, "EQUIPMENT LEASE AGREEMENT")
    c.setFont("Helvetica", 10)
    c.drawString(0.9 * inch, h - 2.05 * inch, "Agreement No. NEF-2025-0917          Date of Agreement: August 15, 2025")

    y = h - 2.5 * inch
    c.setFont("Helvetica-Bold", 10.5)
    c.drawString(0.9 * inch, y, "1. PARTIES")
    c.setFont("Helvetica", 10)
    y -= 0.22 * inch
    c.drawString(1.1 * inch, y, "Lessor:  Northbridge Equipment Finance Inc. (\"Lessor\")")
    y -= 0.2 * inch
    c.drawString(1.1 * inch, y, "Lessee:  Lakeshore Fabrication Ltd., 88 Industrial Crescent, Hamilton, Ontario L8E 2X1 (\"Lessee\")")

    y -= 0.38 * inch
    c.setFont("Helvetica-Bold", 10.5)
    c.drawString(0.9 * inch, y, "2. EQUIPMENT")
    c.setFont("Helvetica", 10)
    y -= 0.22 * inch
    c.drawString(1.1 * inch, y, "One (1) Vertex VMC-850 5-axis CNC machining centre, Serial No. VX850-25-00412, new.")

    # Key terms box
    y -= 0.45 * inch
    c.setFont("Helvetica-Bold", 10.5)
    c.drawString(0.9 * inch, y, "3. FINANCIAL TERMS (all amounts in Canadian dollars, exclusive of HST unless stated)")
    rows = [
        ("Equipment Cost", money(COST)),
        ("Down Payment (due on signing)", money(DOWN)),
        ("HST on Down Payment (13%)", money(DOWN_HST)),
        ("Amount Financed", money(FIN)),
        ("Lease Commencement Date", "September 1, 2025"),
        ("Lease Term", "60 months"),
        ("Implicit Interest Rate", "6.50% per annum"),
        ("Monthly Lease Payment (excl. HST)", money(PMT)),
        ("HST on Monthly Payment (13%)", money(PMT_HST)),
        ("Total Monthly Payment (incl. HST)", money(PMT + PMT_HST)),
        ("First Payment Due", "October 1, 2025"),
        ("Purchase Option at End of Term", "$1.00"),
    ]
    y -= 0.15 * inch
    box_top = y
    rh = 0.27 * inch
    x0, x1, x2 = 1.1 * inch, 4.6 * inch, w - 1.1 * inch
    for i, (k, v) in enumerate(rows):
        yy = box_top - (i + 1) * rh
        if i % 2 == 0:
            c.setFillColor(LIGHT)
            c.rect(x0, yy, x2 - x0, rh, stroke=0, fill=1)
        c.setFillColor(colors.black)
        c.setFont("Helvetica", 10)
        c.drawString(x0 + 0.1 * inch, yy + 0.085 * inch, k)
        c.setFont("Helvetica-Bold", 10)
        c.drawRightString(x2 - 0.15 * inch, yy + 0.085 * inch, v)
    c.setStrokeColor(GREY); c.setLineWidth(0.6)
    c.rect(x0, box_top - len(rows) * rh, x2 - x0, len(rows) * rh, stroke=1, fill=0)
    c.line(x1, box_top, x1, box_top - len(rows) * rh)

    y = box_top - len(rows) * rh - 0.4 * inch
    c.setFont("Helvetica-Bold", 10.5)
    c.drawString(0.9 * inch, y, "4. OWNERSHIP AND MAINTENANCE")
    c.setFont("Helvetica", 9.5)
    text = [
        "Title to the Equipment remains with the Lessor until all payments have been made and the purchase",
        "option is exercised. The Lessee is responsible for insurance, maintenance and repairs during the term.",
        "The estimated useful life of the Equipment is ten (10) years.",
    ]
    for t in text:
        y -= 0.19 * inch
        c.drawString(1.1 * inch, y, t)

    y -= 0.55 * inch
    c.setFont("Helvetica", 9.5)
    c.drawString(1.1 * inch, y, "For the Lessor: ______________________")
    c.drawString(4.4 * inch, y, "For the Lessee: ______________________")
    y -= 0.18 * inch
    c.setFillColor(GREY)
    c.drawString(1.1 * inch, y, "J. Whitfield, Credit Manager")
    c.drawString(4.4 * inch, y, "R. Desai, Controller")
    watermark(c, w, h)
    c.showPage(); c.save()


# --------------------------------------------------------------------------------------
# DEMO 2 - Repairs & maintenance transaction schedule (table + sum demo)
# --------------------------------------------------------------------------------------
TXNS = [
    ("2025-09-04", "PH-20871", "Precision Hydraulics Ltd.", "Hydraulic press seal replacement", 2450.00),
    ("2025-09-18", "GL-5530", "Great Lakes Electrical Inc.", "Panel inspection - Bay 2", 1180.00),
    ("2025-10-02", "PH-20944", "Precision Hydraulics Ltd.", "Pump overhaul - Line 1", 6875.00),
    ("2025-10-21", "NC-1187", "Niagara Compressor Services", "Quarterly compressor service", 940.00),
    ("2025-11-06", "GL-5612", "Great Lakes Electrical Inc.", "Emergency breaker repair", 3215.50),
    ("2025-11-27", "SF-0349", "Steelcity Fire Protection", "Annual sprinkler inspection", 1625.00),
    ("2025-12-09", "PH-21033", "Precision Hydraulics Ltd.", "Hose assemblies and fittings", 1398.75),
    ("2026-01-15", "NC-1240", "Niagara Compressor Services", "Dryer filter replacement", 612.40),
    ("2026-02-03", "GL-5701", "Great Lakes Electrical Inc.", "LED retrofit - Warehouse", 8420.00),
    ("2026-02-24", "PH-21118", "Precision Hydraulics Ltd.", "CNC coolant system repair", 2985.00),
]
TXN_ROWS = [(d, ref, v, desc, net, round(net * 0.13, 2), round(net * 1.13, 2)) for d, ref, v, desc, net in TXNS]


def demo2_pdf(path):
    w, h = letter
    c = canvas.Canvas(path, pagesize=letter)
    c.setTitle("Repairs and Maintenance Schedule - FICTIONAL")
    c.setFillColor(NAVY)
    c.setFont("Helvetica-Bold", 15)
    c.drawString(0.7 * inch, h - 0.95 * inch, "Lakeshore Fabrication Ltd.")
    c.setFont("Helvetica-Bold", 12)
    c.setFillColor(colors.black)
    c.drawString(0.7 * inch, h - 1.22 * inch, "Schedule of Repairs & Maintenance Expenditures (GL 6450)")
    c.setFont("Helvetica", 9.5)
    c.setFillColor(GREY)
    c.drawString(0.7 * inch, h - 1.42 * inch, "For the period September 1, 2025 to February 28, 2026  |  Prepared by: Accounting Dept.  |  Amounts in CAD")

    cols = ["Date", "Invoice #", "Vendor", "Description", "Net", "HST 13%", "Total"]
    xs = [0.7, 1.45, 2.2, 4.05, 6.0, 6.75, 7.45]  # inches, left edges
    right = 8.1
    y = h - 1.85 * inch
    rh = 0.3 * inch
    c.setFillColor(NAVY)
    c.rect(0.7 * inch, y - rh, (right - 0.7) * inch, rh, stroke=0, fill=1)
    c.setFillColor(colors.white)
    c.setFont("Helvetica-Bold", 8.5)
    for i, col in enumerate(cols):
        if i >= 4:
            nxt = xs[i + 1] if i + 1 < len(xs) else right
            c.drawRightString((nxt - 0.06) * inch, y - rh + 0.1 * inch, col)
        else:
            c.drawString((xs[i] + 0.05) * inch, y - rh + 0.1 * inch, col)
    c.setFont("Helvetica", 8.5)
    for j, row in enumerate(TXN_ROWS):
        yy = y - (j + 2) * rh
        if j % 2 == 1:
            c.setFillColor(LIGHT)
            c.rect(0.7 * inch, yy, (right - 0.7) * inch, rh, stroke=0, fill=1)
        c.setFillColor(colors.black)
        vals = [row[0], row[1], row[2], row[3], f"{row[4]:,.2f}", f"{row[5]:,.2f}", f"{row[6]:,.2f}"]
        for i, v in enumerate(vals):
            if i >= 4:
                nxt = xs[i + 1] if i + 1 < len(xs) else right
                c.drawRightString((nxt - 0.06) * inch, yy + 0.1 * inch, v)
            else:
                c.drawString((xs[i] + 0.05) * inch, yy + 0.1 * inch, v)
    # totals
    yy = y - (len(TXN_ROWS) + 2) * rh
    c.setStrokeColor(colors.black); c.setLineWidth(0.8)
    c.line(6.0 * inch, yy + rh, right * inch, yy + rh)
    c.setFont("Helvetica-Bold", 8.5)
    c.drawString(0.75 * inch, yy + 0.1 * inch, "TOTAL")
    tots = [sum(r[k] for r in TXN_ROWS) for k in (4, 5, 6)]
    for i, v in zip((4, 5, 6), tots):
        nxt = xs[i + 1] if i + 1 < len(xs) else right
        c.drawRightString((nxt - 0.06) * inch, yy + 0.1 * inch, f"{v:,.2f}")
    c.line(6.0 * inch, yy - 0.02 * inch, right * inch, yy - 0.02 * inch)
    c.line(6.0 * inch, yy - 0.05 * inch, right * inch, yy - 0.05 * inch)

    c.setFont("Helvetica", 8.5)
    c.setFillColor(GREY)
    c.drawString(0.7 * inch, yy - 0.45 * inch, "HST calculated at the Ontario harmonized rate of 13%. Balance agrees to general ledger account 6450 at February 28, 2026.")
    watermark(c, w, h)
    c.showPage(); c.save()


# --------------------------------------------------------------------------------------
# EXERCISE - Vendor invoice (rendered as a "scanned" image-only PDF so OCR is relevant)
# --------------------------------------------------------------------------------------
INV_LINES = [
    ("WG-4410", "Welding gloves, heavy duty (box of 12)", 8, 46.50),
    ("CW-0225", "Cutting wheels 4.5 in. (pack of 25)", 12, 38.90),
    ("SG-1180", "Safety glasses, anti-fog", 40, 9.75),
    ("AB-7720", "Absorbent spill kit, 55 gal", 2, 289.00),
    ("RT-0001", "Return credit - damaged spill kit (RMA 5521)", 1, -289.00),
]
INV_LINES = [(a, b, q, p, round(q * p, 2)) for a, b, q, p in INV_LINES]
INV_SUB = round(sum(l[4] for l in INV_LINES), 2)
INV_HST = round(INV_SUB * 0.13, 2)
INV_TOT = round(INV_SUB + INV_HST, 2)


def exercise_vector_pdf(path):
    w, h = letter
    c = canvas.Canvas(path, pagesize=letter)
    c.setFillColor(GREEN)
    c.setFont("Helvetica-Bold", 17)
    c.drawString(0.8 * inch, h - 0.95 * inch, "Maple Ridge Industrial Supply Inc.")
    c.setFont("Helvetica", 9)
    c.setFillColor(GREY)
    c.drawString(0.8 * inch, h - 1.15 * inch, "2201 Escarpment Drive, Burlington, Ontario L7L 0B4  |  HST Reg. No. 79876 5432 RT0001")
    c.setFillColor(colors.black)
    c.setFont("Helvetica-Bold", 20)
    c.drawRightString(w - 0.8 * inch, h - 0.95 * inch, "INVOICE")

    c.setFont("Helvetica", 10)
    y = h - 1.7 * inch
    c.drawString(0.8 * inch, y, "Bill To:")
    c.setFont("Helvetica-Bold", 10)
    c.drawString(0.8 * inch, y - 0.2 * inch, "Lakeshore Fabrication Ltd.")
    c.setFont("Helvetica", 10)
    c.drawString(0.8 * inch, y - 0.38 * inch, "88 Industrial Crescent")
    c.drawString(0.8 * inch, y - 0.56 * inch, "Hamilton, Ontario  L8E 2X1")

    meta = [("Invoice No.:", "INV-40217"), ("Invoice Date:", "October 14, 2025"), ("Customer PO:", "LF-PO-3386"), ("Terms:", "Net 30")]
    for i, (k, v) in enumerate(meta):
        c.setFont("Helvetica", 10)
        c.drawString(5.0 * inch, y - i * 0.2 * inch, k)
        c.setFont("Helvetica-Bold", 10)
        c.drawRightString(w - 0.8 * inch, y - i * 0.2 * inch, v)

    y = h - 2.7 * inch
    rh = 0.32 * inch
    cols = [("Item", 0.8), ("Description", 1.65), ("Qty", 5.05), ("Unit Price", 5.85), ("Amount", 7.0)]
    right = w / inch - 0.8
    c.setFillColor(GREEN)
    c.rect(0.8 * inch, y - rh, (right - 0.8) * inch, rh, stroke=0, fill=1)
    c.setFillColor(colors.white)
    c.setFont("Helvetica-Bold", 9.5)
    c.drawString(0.88 * inch, y - rh + 0.11 * inch, "Item")
    c.drawString(1.73 * inch, y - rh + 0.11 * inch, "Description")
    c.drawRightString(5.5 * inch, y - rh + 0.11 * inch, "Qty")
    c.drawRightString(6.7 * inch, y - rh + 0.11 * inch, "Unit Price")
    c.drawRightString((right - 0.08) * inch, y - rh + 0.11 * inch, "Amount")
    c.setFont("Helvetica", 9.5)
    c.setFillColor(colors.black)
    for j, (item, desc, q, p, amt) in enumerate(INV_LINES):
        yy = y - (j + 2) * rh
        c.setStrokeColor(colors.HexColor("#CCCCCC")); c.setLineWidth(0.5)
        c.line(0.8 * inch, yy, right * inch, yy)
        c.drawString(0.88 * inch, yy + 0.11 * inch, item)
        c.drawString(1.73 * inch, yy + 0.11 * inch, desc)
        c.drawRightString(5.5 * inch, yy + 0.11 * inch, str(q))
        c.drawRightString(6.7 * inch, yy + 0.11 * inch, f"{p:,.2f}" if p >= 0 else f"({abs(p):,.2f})")
        c.drawRightString((right - 0.08) * inch, yy + 0.11 * inch, f"{amt:,.2f}" if amt >= 0 else f"({abs(amt):,.2f})")

    yy = y - (len(INV_LINES) + 2) * rh - 0.15 * inch
    for k, v, bold in [("Subtotal", INV_SUB, False), ("HST (13%)", INV_HST, False), ("TOTAL DUE (CAD)", INV_TOT, True)]:
        c.setFont("Helvetica-Bold" if bold else "Helvetica", 10.5 if bold else 10)
        c.drawString(5.2 * inch, yy, k)
        c.drawRightString((right - 0.08) * inch, yy, f"${v:,.2f}")
        yy -= 0.26 * inch
    c.setFont("Helvetica", 9)
    c.setFillColor(GREY)
    c.drawString(0.8 * inch, yy - 0.3 * inch, "Payment by EFT to account on file. Amounts in parentheses are credits. Thank you for your business.")
    watermark(c, w, h)
    c.showPage(); c.save()


def scanify(vector_pdf, out_pdf):
    """Rasterise the vector invoice and add mild scan artefacts (slight skew, grey noise)
    so that the document has no text layer and must be OCR'd - mirrors real client scans."""
    from PIL import Image, ImageFilter
    import subprocess, tempfile
    tmp = tempfile.mkdtemp()
    subprocess.run(["pdftoppm", "-r", "150", "-png", "-singlefile", vector_pdf, os.path.join(tmp, "p")], check=True)
    img = Image.open(os.path.join(tmp, "p.png")).convert("L")
    img = img.rotate(0.6, expand=False, fillcolor=255, resample=Image.BICUBIC)
    random.seed(7)
    px = img.load()
    W, H = img.size
    for _ in range(int(W * H * 0.0015)):
        x, y = random.randrange(W), random.randrange(H)
        px[x, y] = random.randint(150, 210)
    img = img.filter(ImageFilter.GaussianBlur(0.35))
    img.save(out_pdf, "PDF", resolution=150.0)


# --------------------------------------------------------------------------------------
# Workbooks
# --------------------------------------------------------------------------------------
HDR_FILL = PatternFill("solid", fgColor="14284B")
DEST_FILL = PatternFill("solid", fgColor="E3F1E8")
NOTE_FONT = Font(italic=True, color="C0392B", size=9)
THIN = Side(style="thin", color="A0A8B4")
BOX = Border(left=THIN, right=THIN, top=THIN, bottom=THIN)


def hdr(ws, row, values, col=1):
    for i, v in enumerate(values):
        cell = ws.cell(row=row, column=col + i, value=v)
        cell.font = Font(bold=True, color="FFFFFF")
        cell.fill = HDR_FILL
        cell.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
        cell.border = BOX


def title(ws, text, sub):
    ws["A1"] = text
    ws["A1"].font = Font(bold=True, size=14, color="14284B")
    ws["A2"] = sub
    ws["A2"].font = NOTE_FONT


def demo_workbook(path, answers=False):
    wb = Workbook()
    ws = wb.active
    ws.title = "Lease_Extraction"
    title(ws, "Demo 1 - Equipment Lease Extraction Worksheet (FICTIONAL)",
          "Fictional client Lakeshore Fabrication Ltd. - training data only. Green cells = Extractly destination cells.")
    hdr(ws, 4, ["Field", "Extractly method", "Destination (extract here)", "Source location in PDF", "Preparer check (tick-mark / initials)"])
    fields = [
        ("Equipment Cost", "Text", COST, "Section 3, row 'Equipment Cost'"),
        ("Down Payment", "Text", DOWN, "Section 3, row 'Down Payment (due on signing)'"),
        ("Lease Commencement Date", "Text", "September 1, 2025", "Section 3, row 'Lease Commencement Date'"),
    ]
    for i, (f, m, v, loc) in enumerate(fields):
        r = 5 + i
        ws.cell(row=r, column=1, value=f).border = BOX
        ws.cell(row=r, column=2, value=m).border = BOX
        dc = ws.cell(row=r, column=3, value=v if answers else None)
        dc.fill = DEST_FILL; dc.border = BOX
        if isinstance(v, float):
            dc.number_format = '$#,##0.00'
        ws.cell(row=r, column=4, value=loc).border = BOX
        ws.cell(row=r, column=5).border = BOX

    ws["A10"] = "Independent recalculations (Excel formulas - NOT Extractly)"
    ws["A10"].font = Font(bold=True, color="14284B")
    calc = [
        ("Amount financed (=C5-C6)", "=C5-C6"),
        ("HST on equipment cost at 13% (=C5*13%)", "=C5*0.13"),
        ("HST on down payment at 13% (=C6*13%)", "=C6*0.13"),
        ("Monthly payment per agreement (enter manually or extract)", None),
        ("PV of 60 payments at 6.5%/12 (=PV(6.5%/12,60,-C14))", "=PV(0.065/12,60,-C14)"),
        ("PV of min. lease payments incl. down payment (=C15+C6)", "=C15+C6"),
        ("PV as % of equipment fair value (=C16/C5)", "=IFERROR(C16/C5,0)"),
    ]
    for i, (lbl, f) in enumerate(calc):
        r = 11 + i
        ws.cell(row=r, column=1, value=lbl).border = BOX
        cell = ws.cell(row=r, column=3, value=f if f else (PMT if answers else None))
        cell.border = BOX
        cell.number_format = '0.0%' if "%" in lbl and "PV as" in lbl else '$#,##0.00'
        if f is None:
            cell.fill = DEST_FILL
    ws["A19"] = ("Illustrative only: capital lease indicators under ASPE Section 3065 include transfer of ownership/bargain purchase option, "
                 "lease term >= 75% of economic life, or PV of minimum lease payments >= 90% of fair value. Apply Melo LLP methodology and the applicable framework (ASPE / IFRS 16).")
    ws["A19"].font = NOTE_FONT
    ws["A19"].alignment = Alignment(wrap_text=True, vertical="top")
    ws.merge_cells("A19:E21")
    for col, wd in zip("ABCDE", (52, 16, 26, 44, 30)):
        ws.column_dimensions[col].width = wd

    # Demo 2 sheet
    ws2 = wb.create_sheet("RM_Schedule")
    title(ws2, "Demo 2 - Repairs & Maintenance Schedule (FICTIONAL)",
          "Extract the table with Extractly 'Table': select cell A5 as the upper-left destination cell. Do not type over the green area.")
    ws2["A4"] = "Extracted table starts at A5 (header row included)"
    ws2["A4"].font = Font(bold=True, color="2E7D4F")
    if answers:
        hdr(ws2, 5, ["Date", "Invoice #", "Vendor", "Description", "Net", "HST 13%", "Total"])
        for j, row in enumerate(TXN_ROWS):
            for i, v in enumerate(row):
                c = ws2.cell(row=6 + j, column=1 + i, value=v)
                c.border = BOX
                if i >= 4:
                    c.number_format = '#,##0.00'
    else:
        for rr in range(5, 17):
            for cc in range(1, 8):
                ws2.cell(row=rr, column=cc).fill = DEST_FILL
    ws2["I4"] = "Independent checks (Excel formulas)"
    ws2["I4"].font = Font(bold=True, color="14284B")
    checks = [
        ("Sum of Net (extracted rows)", "=SUM(E6:E15)"),
        ("Sum of HST (extracted rows)", "=SUM(F6:F15)"),
        ("HST recalculated (=Net x 13%)", "=ROUND(SUM(E6:E15)*0.13,2)"),
        ("Difference HST vs recalc (expect 0.00)", "=ROUND(J6-J7,2)"),
        ("Total per schedule (type from PDF total row)", None),
        ("Difference vs schedule total (expect 0.00)", "=ROUND(SUM(G6:G15)-J9,2)"),
        ("Extractly SUM: Precision Hydraulics Net (destination)", None),
        ("Independent SUMIF - Precision Hydraulics Net", '=SUMIF(C6:C15,"Precision Hydraulics Ltd.",E6:E15)'),
        ("Difference (expect 0.00)", "=ROUND(J11-J12,2)"),
    ]
    tot_total = round(sum(r[6] for r in TXN_ROWS), 2)
    ph_sum = round(sum(r[4] for r in TXN_ROWS if r[2].startswith("Precision")), 2)
    for i, (lbl, f) in enumerate(checks):
        r = 5 + i
        ws2.cell(row=r, column=9, value=lbl).border = BOX
        val = f
        if f is None:
            val = (tot_total if "schedule" in lbl else ph_sum) if answers else None
        c = ws2.cell(row=r, column=10, value=val)
        c.border = BOX; c.number_format = '#,##0.00'
        if f is None:
            c.fill = DEST_FILL
    for col, wd in zip("ABCDEFGHIJ", (12, 11, 28, 34, 12, 11, 12, 3, 50, 16)):
        ws2.column_dimensions[col].width = wd
    wb.save(path)


def exercise_workbook(path, answers=False):
    wb = Workbook()
    ws = wb.active
    ws.title = "Exercise"
    title(ws, ("ANSWER KEY - " if answers else "") + "Participant Exercise - Vendor Invoice INV-40217 (FICTIONAL)",
          "Source file: Exercise_Vendor_Invoice_SCANNED.pdf  |  Fictional data for training only. Green cells = your Extractly destinations.")
    ws["A3"] = "Participant name:"; ws["B3"].fill = DEST_FILL
    hdr(ws, 5, ["Task", "Field", "Extractly method", "Your result (destination)", "Matches PDF? (Y/N)"])
    t = [
        ("1", "Invoice number", "Text", "INV-40217"),
        ("2", "Invoice date", "Text", "October 14, 2025"),
        ("3", "Total due (incl. HST)", "Text", INV_TOT),
    ]
    for i, (n, f, m, v) in enumerate(t):
        r = 6 + i
        for cc, val in enumerate([n, f, m], start=1):
            ws.cell(row=r, column=cc, value=val).border = BOX
        d = ws.cell(row=r, column=4, value=v if answers else None)
        d.fill = DEST_FILL; d.border = BOX
        if isinstance(v, float):
            d.number_format = '$#,##0.00'
        ws.cell(row=r, column=5, value="Y" if answers else None).border = BOX

    ws["A10"] = "Task 4 - Extract the line-item table here (Extractly 'Table'): upper-left destination cell = A11"
    ws["A10"].font = Font(bold=True, color="2E7D4F")
    if answers:
        hdr(ws, 11, ["Item", "Description", "Qty", "Unit Price", "Amount"])
        for j, (a, b, q, p, amt) in enumerate(INV_LINES):
            for i, v in enumerate([a, b, q, p, amt]):
                c = ws.cell(row=12 + j, column=1 + i, value=v); c.border = BOX
                if i >= 3:
                    c.number_format = '#,##0.00;(#,##0.00)'
    else:
        for rr in range(11, 17):
            for cc in range(1, 6):
                ws.cell(row=rr, column=cc).fill = DEST_FILL

    ws["A19"] = "Task 5 - Verification (Excel formulas, independent of Extractly)"
    ws["A19"].font = Font(bold=True, color="14284B")
    v = [
        ("Recalculated subtotal (=SUM(E12:E16))", "=SUM(E12:E16)"),
        ("Recalculated HST at 13%", "=ROUND(B20*0.13,2)"),
        ("Recalculated total", "=B20+B21"),
        ("Difference vs extracted total D8 (expect 0.00)", "=ROUND(B22-D8,2)"),
        ("Each line: Qty x Unit Price = Amount? (count of exceptions)", "=SUMPRODUCT(--(ROUND(C12:C16*D12:D16,2)<>ROUND(E12:E16,2)))"),
    ]
    for i, (lbl, f) in enumerate(v):
        r = 20 + i
        ws.cell(row=r, column=1, value=lbl).border = BOX
        c = ws.cell(row=r, column=2, value=f); c.border = BOX
        c.number_format = '0' if "count" in lbl else '$#,##0.00;($#,##0.00)'

    ws["A26"] = "Task 6 - Describe ONE OCR or data-extraction risk you observed and how you addressed it:"
    ws["A26"].font = Font(bold=True, color="14284B")
    ws.merge_cells("A27:E30")
    ws["A27"].fill = DEST_FILL
    ws["A27"].alignment = Alignment(wrap_text=True, vertical="top")
    if answers:
        ws["A27"] = ("Example answer: The credit line RT-0001 is shown in parentheses (289.00). OCR/extraction may return it as text or as a positive number, "
                     "overstating the subtotal by $578.00. I confirmed the sign against the source PDF and the subtotal recalculation (difference 0.00). "
                     "Other acceptable risks: scanned/skewed image misreads (e.g. 0 vs O, 1 vs l, 5 vs S), dropped/merged table rows, date read as text, "
                     "dollar signs/commas causing values to import as text, partial selection box missing a digit.")
    for col, wd in zip("ABCDE", (50, 44, 16, 26, 18)):
        ws.column_dimensions[col].width = wd
    wb.save(path)


if __name__ == "__main__":
    demo1_pdf(os.path.join(MAT, "Demo1_Equipment_Lease_Agreement_FICTIONAL.pdf"))
    demo2_pdf(os.path.join(MAT, "Demo2_RM_Transaction_Schedule_FICTIONAL.pdf"))
    vec = os.path.join(MAT, "_exercise_vector.pdf")
    exercise_vector_pdf(vec)
    scanify(vec, os.path.join(MAT, "Exercise_Vendor_Invoice_SCANNED_FICTIONAL.pdf"))
    os.replace(vec, os.path.join(MAT, "Exercise_Vendor_Invoice_CLEAN_FICTIONAL.pdf"))
    demo_workbook(os.path.join(MAT, "Demo_Workbook_Participant.xlsx"), answers=False)
    demo_workbook(os.path.join(MAT, "Demo_Workbook_Instructor_Completed.xlsx"), answers=True)
    exercise_workbook(os.path.join(MAT, "Exercise_Workbook_Participant.xlsx"), answers=False)
    exercise_workbook(os.path.join(MAT, "Exercise_Workbook_ANSWER_KEY.xlsx"), answers=True)
    print("PMT", PMT, "PMT_HST", PMT_HST, "DOWN_HST", DOWN_HST)
    print("R&M net", round(sum(r[4] for r in TXN_ROWS), 2), "hst", round(sum(r[5] for r in TXN_ROWS), 2), "tot", round(sum(r[6] for r in TXN_ROWS), 2))
    print("PH net", round(sum(r[4] for r in TXN_ROWS if r[2].startswith('Precision')), 2))
    print("INV sub", INV_SUB, "hst", INV_HST, "tot", INV_TOT)
