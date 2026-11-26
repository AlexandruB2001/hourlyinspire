"""Instructor checklist (1 page) and Screenshot capture checklist as editable DOCX."""
import os
from docx import Document
from docx.shared import Pt, Inches, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.section import WD_ORIENT
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "supporting")
os.makedirs(OUT, exist_ok=True)
NAVY = RGBColor(0x14, 0x28, 0x4B)
GREEN = RGBColor(0x2E, 0x7D, 0x4F)
GREY = RGBColor(0x5F, 0x6B, 0x7A)
BOX = "☐ "


def base(landscape=False, margin=0.6):
    d = Document()
    st = d.styles["Normal"]
    st.font.name = "Calibri"
    st.font.size = Pt(10)
    st.element.rPr.rFonts.set(qn("w:eastAsia"), "Calibri")
    sec = d.sections[0]
    if landscape:
        sec.orientation = WD_ORIENT.LANDSCAPE
        sec.page_width, sec.page_height = Inches(11), Inches(8.5)
    for side in ("left_margin", "right_margin", "top_margin", "bottom_margin"):
        setattr(sec, side, Inches(margin))
    return d


def h(d, text, size=14, color=NAVY, before=6, after=2):
    p = d.add_paragraph()
    p.paragraph_format.space_before = Pt(before)
    p.paragraph_format.space_after = Pt(after)
    r = p.add_run(text)
    r.bold = True; r.font.size = Pt(size); r.font.color.rgb = color
    return p


def line(d, text, size=10, bold_prefix=None, color=None, after=1, indent=0):
    p = d.add_paragraph()
    p.paragraph_format.space_after = Pt(after)
    p.paragraph_format.space_before = Pt(0)
    if indent:
        p.paragraph_format.left_indent = Inches(indent)
    if bold_prefix:
        r = p.add_run(bold_prefix); r.bold = True; r.font.size = Pt(size)
    r = p.add_run(text); r.font.size = Pt(size)
    if color:
        r.font.color.rgb = color
    return p


def shade(cell, hexcolor):
    tcPr = cell._tc.get_or_add_tcPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear"); shd.set(qn("w:color"), "auto"); shd.set(qn("w:fill"), hexcolor)
    tcPr.append(shd)


def table(d, rows, widths, size=9):
    t = d.add_table(rows=len(rows), cols=len(rows[0]))
    t.style = "Table Grid"
    t.autofit = False
    for j, w in enumerate(widths):
        t.columns[j].width = Inches(w)
    for i, row in enumerate(rows):
        for j, v in enumerate(row):
            c = t.cell(i, j)
            c.width = Inches(widths[j])
            c.text = ""
            p = c.paragraphs[0]
            p.paragraph_format.space_after = Pt(0)
            r = p.add_run(str(v)); r.font.size = Pt(size)
            if i == 0:
                r.bold = True; r.font.color.rgb = RGBColor(0xFF, 0xFF, 0xFF); shade(c, "14284B")
    return t


# ------------------------------------------------------------------ Instructor checklist (1 page)
d = base(margin=0.5)
h(d, "Instructor Checklist: Caseware Extractly Training (Melo LLP | 2026)", 14, before=0)
line(d, "Deck: Extractly_Training_Melo_LLP_2026.pptx (20 slides, ~35–38 min instruction + 15-min exercise). "
        "Full script is in the speaker notes.", 9, color=GREY, after=3)

h(d, "One week before", 11, GREEN, before=2)
for t in ["Capture screenshots SS-01 to SS-07 using the Screenshot Capture Checklist, insert them, and delete the placeholders.",
          "Insert the approved Melo LLP logo on slide 1 (or delete the placeholder). Add the internal contact on slide 20.",
          "Check Caseware's “What's new” page and re-verify command names and limits (15 MB; PDF/PNG/JPG; XLSX; internet).",
          "Confirm with IT that every participant has the Extractly add-in, a subscription and a Microsoft 365 business/enterprise licence.",
          "Copy the /materials folder to a shared training location. Keep the ANSWER_KEY files and the CLEAN PDF for instructors only."]:
    line(d, t, 9.5, BOX)

h(d, "30 minutes before", 11, GREEN, before=3)
for t in ["Excel signed in with your Melo account; internet confirmed; Extractly | Open shows the sidebar.",
          "Demo_Workbook_Participant.xlsx open (tabs Lease_Extraction and RM_Schedule; green cells empty). Excel zoom ~120%.",
          "Demo1 PDF NOT yet uploaded (you will show the upload). Demo2 PDF optionally pre-uploaded.",
          "Backup open: Demo_Workbook_Instructor_Completed.xlsx, in case of connectivity problems.",
          "Notifications off; no client files or client workbooks visible on screen; presenter view on."]:
    line(d, t, 9.5, BOX)

h(d, "Run of show", 11, GREEN, before=3)
table(d, [
    ["Slides", "Segment", "Min", "Must-do"],
    ["1–2", "Welcome, objectives", "2.5", "State that all data is fictional; gauge experience"],
    ["3–4", "What Extractly is; workflow", "4", "Read: “Extracting a value is not validating audit evidence…”"],
    ["5–7", "Setup, interface, upload", "6", "Show Extractly | Open; Upload Files › Process; 15 MB / XLSX"],
    ["8–9", "Text + Demo #1 (lease)", "6", "C5:C7; deliberate wrong box; Ctrl+Z vs ribbon Undo; trace C6"],
    ["10–11", "Table + Demo #2 (R&M schedule)", "5", "A5, 11 rows × 7 cols; checks J5:J10 = 0.00"],
    ["12–13", "Sum; traceability", "4", "Ctrl multi-select → 13,708.75 vs SUMIF; cell ↔ source both ways"],
    ["14–15", "Advanced; additional functions", "4.5", "Label as optional; fuzzy match = lead, not match"],
    ["16–18", "Applications; errors; best practices", "5.5", "“Extractly captures data. You evaluate evidence.”"],
    ["19", "Participant exercise", "15+3", "Circulate; debrief one risk each from 2–3 people"],
    ["20", "Summary, Q&A, resources", "2+Q&A", "Point to the official links; log unanswered questions"],
], [0.6, 2.2, 0.55, 4.15], size=8.5)

h(d, "Expected results (answer keys)", 11, GREEN, before=4)
line(d, "C5 $116,000.00 · C6 $18,000.00 · C7 September 1, 2025 · amount financed $98,000.00 · PV/FV 100%", 9.5, "Demo #1: ")
line(d, "Net 29,701.65 · HST 3,861.21 · Total 33,562.86 · Precision Hydraulics Sum 13,708.75 · all differences 0.00", 9.5, "Demo #2: ")
line(d, "INV-40217 · October 14, 2025 · $1,715.11 · 5 lines incl. credit (289.00) · subtotal 1,517.80 · HST 197.31", 9.5, "Exercise: ")

h(d, "Common in-room issues", 11, GREEN, before=4)
for t in ["No Process pressed → file never uploads.   Cell chosen before the command → nothing extracts; follow command → cell → box.",
          "Ctrl+Z used → extraction not undone; use the ribbon Undo.   Totals row inside the Table box → the total is double-counted in the checks.",
          "OCR outage for the room → switch to Exercise_Vendor_Invoice_CLEAN_FICTIONAL.pdf and continue."]:
    line(d, t, 9, "• ")

h(d, "After the session", 11, GREEN, before=4)
for t in ["Remove the training files from the Extractly sidebar if your firm policy requires it; record attendance/CPD hours.",
          "Log unanswered questions and send them to Caseware support (Provide feedback or request support page) or the internal champion."]:
    line(d, t, 9.5, BOX)
d.save(os.path.join(OUT, "Instructor_Checklist_Extractly_Training.docx"))

# ------------------------------------------------------------------ Screenshot capture checklist
d = base(landscape=True, margin=0.5)
h(d, "Screenshot Capture Checklist: Extractly Training Deck", 15, before=0)
line(d, "No Extractly interface screenshots were supplied, so none have been fabricated. Every interface image in the "
        "deck is a clearly marked placeholder (“INSERT ACTUAL MELO EXCEL SCREENSHOT HERE”). Capture each one from Melo's own "
        "Excel/Extractly environment using ONLY the fictional training files.", 9.5, after=4)
h(d, "Capture rules", 11, GREEN, before=2)
for t in ["Use the fictional files in /materials only. Never show client names, real workbooks, email, Teams or file paths that identify clients.",
          "Use a 1920×1080 display at 100% Windows scaling; Excel zoom 100–120%. Use PNG format (Windows: Win+Shift+S). Do not edit button labels or interface text.",
          "Crop to the relevant area; keep labels readable at presentation size. Where noted, add a zoomed inset (a second, tighter crop).",
          "To insert: on the slide, Insert › Pictures, size the picture over the dashed box, then delete the placeholder shapes "
          "(Home › Arrange › Selection Pane: items named “SS-xx …”). Drag the numbered navy callouts onto the matching interface elements.",
          "Record the Extractly/Excel version and the capture date in the slide notes; recapture when Caseware changes the interface."]:
    line(d, t, 9.5, "• ")
h(d, "Required screenshots", 11, GREEN, before=4)
rows = [["ID", "Slide", "What to capture (exact state)", "Callouts to place", "Captured"],
        ["SS-01", "5", "Excel ribbon at full width with the Extractly tab/group visible and the Open command. Zoomed inset of Open.",
         "4 = Extractly | Open", BOX],
        ["SS-02", "6", "Full Excel window: Extractly sidebar open with Demo1 PDF displayed; worksheet with an extracted cell selected; "
                       "Extractly ribbon commands visible.", "1 ribbon · 2 file list · 3 document view · 4 worksheet · 5 Link icon/list", BOX],
        ["SS-03", "7", "Sidebar after Upload Files: drop area, Browse, Process. Inset: file list with Demo1 file and its upload-status icon.",
         "2 Upload Files · 3 Browse · 4 Process · 6 status icon", BOX],
        ["SS-04", "8", "Text extraction: selection box around $116,000.00 in the sidebar and C5 populated. Inset: Text button on the ribbon.",
         "2 Text · 3 cell C5 · 4 selection box", BOX],
        ["SS-05", "10", "Table: rectangle around the Demo2 schedule (header + 10 rows), table at A5, Table settings icon (inset). "
                        "Optional second crop: Advanced table formatting dialog.", "2 Table · 3 A5 · 4 rectangle · 6 Table settings", BOX],
        ["SS-06", "12", "Sum: four Ctrl-selected boxes on the Precision Hydraulics Net amounts and 13,708.75 in J11.",
         "1 Sum · 4 Ctrl boxes · 5 result", BOX],
        ["SS-07", "13", "Cell Lease_Extraction!C6 selected and the corresponding extraction range highlighted in the sidebar. "
                        "Second crop: the Link (icon) list of extraction links.", "1 selected cell · 2 highlighted range", BOX]]
table(d, rows, [0.55, 0.45, 5.2, 2.9, 0.8])
h(d, "Optional screenshots (backup or appendix slides; not placed in the deck)", 11, GREEN, before=6)
rows = [["ID", "Slide", "What to capture", "Captured"],
        ["SS-08", "14", "Automated Extraction window showing the Extract per file / Extract per page dropdown and the Save as new template button.", BOX],
        ["SS-09", "14", "Data Match: column-mapping step, with More actions showing Must find this data and Fuzzy text matching.", BOX],
        ["SS-10", "15", "Validation ✓ and Exception ✗ marks in worksheet cells.", BOX],
        ["SS-11", "15", "Sidebar More actions menu next to a file (Run OCR, Move, Save to local, Export modified file / Export original file).", BOX],
        ["SS-12", "15", "Redact prompt showing Confirm Redact (use the fictional invoice only).", BOX]]
table(d, rows, [0.55, 0.45, 8.1, 0.8])
line(d, "Caseware documentation images: none were embedded, because the provenance and licensing of the page images "
        "could not be confirmed for redistribution. Link to the official pages instead (slide 20).", 9, color=GREY, after=0)
d.save(os.path.join(OUT, "Screenshot_Capture_Checklist.docx"))
print("ok")
