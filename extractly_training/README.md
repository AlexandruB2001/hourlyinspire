# Caseware Extractly – Practical Training for Accounting Professionals (Melo LLP | 2026)

## Deliverables

| File | Purpose |
|---|---|
| `Extractly_Training_Melo_LLP_2026.pptx` | Editable 20-slide deck (16:9). Full presenter script in the speaker notes of every slide, plus demo checklists and the exercise answer key in the notes. |
| `Extractly_Training_Melo_LLP_2026.pdf` | PDF version of the deck (rendered with LibreOffice, so fonts may differ slightly from PowerPoint). |
| `supporting/Instructor_Checklist_Extractly_Training.docx` / `.pdf` | One-page instructor checklist: preparation, run of show, answer keys, in-room issues. |
| `supporting/Screenshot_Capture_Checklist.docx` / `.pdf` | The screenshots still to capture (SS-01 to SS-07 required, SS-08 to SS-12 optional), with capture rules. |
| `materials/Demo1_Equipment_Lease_Agreement_FICTIONAL.pdf` | Demo #1 source: equipment $116,000, down payment $18,000, commencement September 1, 2025. |
| `materials/Demo2_RM_Transaction_Schedule_FICTIONAL.pdf` | Demo #2 (Table and Sum) source: 10-line R&M schedule with 13% HST. |
| `materials/Demo_Workbook_Participant.xlsx` / `Demo_Workbook_Instructor_Completed.xlsx` | Companion workbook. Green cells are the extraction destinations; columns I:J and rows 11–17 hold independent checks. |
| `materials/Exercise_Vendor_Invoice_SCANNED_FICTIONAL.pdf` | Participant exercise source. It is an image-only PDF, so OCR applies. |
| `materials/Exercise_Vendor_Invoice_CLEAN_FICTIONAL.pdf` | Instructor-only backup (vector text). |
| `materials/Exercise_Workbook_Participant.xlsx` / `Exercise_Workbook_ANSWER_KEY.xlsx` | Exercise workbook and answer key. |
| `build/` | Scripts that regenerate everything: `make_materials.py`, `build_deck.py`, `make_supporting.py`. |

All client names, documents and amounts are fictional.

## Before presenting

1. Capture and insert the screenshots listed in `supporting/Screenshot_Capture_Checklist`. Each placeholder in the deck is labelled
   **"INSERT ACTUAL MELO EXCEL SCREENSHOT HERE"**. No Extractly interface image has been fabricated.
2. Insert the approved Melo LLP logo on slide 1 (or delete the placeholder), and add the internal contact on slide 20.
3. Check Caseware's *What's new* page for interface changes.

## Verified product facts (official Caseware documentation, checked November 2026)

- 15 MB maximum per PDF or image file. A warning appears if a file exceeds it (System requirements; Get started, staff).
- Image types .png and .jpeg/.jpg. Only XLSX workbooks are supported; XLS and CSV are not (System requirements).
- An active internet connection is always required. Requires Windows 10/11 64-bit and a Microsoft 365 business/enterprise licence; E1 is not supported. Mac is not listed.
- Uploaded files are automatically processed with OCR, and Run OCR reprocesses a file (Run OCR).
- Undo and Redo are on the ribbon. "Keyboard shortcuts (i.e. Ctrl+Z, Ctrl+Y) apply only to Excel actions, not to extractions" (Manage extractions).
- Embedding files keeps extractions working if source files are moved or deleted (Embed files into Excel).
- Data Match offers General and Sequential Match, column mapping, Must find this data, and Fuzzy text matching (Data match).
- Automated Extraction offers templates and Extract per file / Extract per page (Automated extraction).

## Official sources

- Index: https://www.caseware.com/docs/en/cloud/caseware-extractly/caseware-extractly-index
- Get started (staff): https://www.caseware.com/docs/en/cloud/caseware-extractly/get-started/get-started-with-caseware-extractly-staff
- System requirements: https://www.caseware.com/docs/en/cloud/caseware-extractly/systemreqs
- Extract text / table / sum: https://www.caseware.com/docs/en/cloud/caseware-extractly/data-extraction/extract-text · …/extract-a-table · …/extract-a-sum
- Manage extractions: https://www.caseware.com/docs/en/cloud/caseware-extractly/data-extraction/manage-extractions
- Validation and exception: https://www.caseware.com/docs/en/cloud/caseware-extractly/data-extraction/validation-and-exception
- Data match: https://www.caseware.com/docs/en/cloud/caseware-extractly/data-extraction/data-match
- Automated extraction: https://www.caseware.com/docs/en/cloud/caseware-extractly/data-extraction/automated-extraction
- Redact: https://www.caseware.com/docs/en/cloud/caseware-extractly/data-extraction/redact-information
- Organize / Run OCR / Comment / Embed / Export: https://www.caseware.com/docs/en/cloud/caseware-extractly/manage-files/organize-files · …/run-ocr · …/comment-on-files · …/embed-files-into-excel · …/export-files
- Product page: https://www.caseware.com/products/extractly/

## Rebuild

```bash
cd build && python3 make_materials.py && python3 build_deck.py && python3 make_supporting.py
```
