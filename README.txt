STUDYNOTES STORE — SECURE SUPABASE VERSION

1. Upload index.html to your Netlify site.
2. Run setup.sql ONCE in Supabase SQL Editor.
3. Create the admin email/password account in Supabase Authentication.
4. Add that Auth user's UUID to public.admin_users (instructions are at the end of setup.sql).
5. The public site shows Student Store only.
6. Open your same site URL with #admin to reach the Admin Login screen.
7. Only an account present in public.admin_users can enter the Admin Panel.
8. Payment / QR Settings appear only after successful admin verification.
9. Students can still buy a published note and submit UTR/payment proof.
10. Keep notes-pdfs PRIVATE.

IMPORTANT:
- Never put a Supabase secret/service-role key in index.html.
- The secure UI/RLS setup protects Admin operations from ordinary authenticated users.
- For fully secure paid-PDF delivery, use a Supabase Edge Function/server endpoint to verify
  the paid order and create a short-lived signed URL for the private PDF.


PREVIOUS YEAR PAPERS:
11. Run the updated setup.sql in Supabase SQL Editor.
12. The website now has a "Previous Year Papers" section.
13. Admin Panel has a separate upload form for old question-paper PDFs.
14. Enter year, class/exam, subject, title and upload the PDF.
15. Published papers appear for students and can be opened in Chrome/PDF viewer.
16. The previous-year-papers bucket is PUBLIC because these papers are intended as free student resources.


V2 EXAM TYPE:
- Previous Year Papers now include Exam Type.
- Options: Half-Yearly, Annual, Pre-Board, Practice, Unit Test, Board Exam, Other.
- Students can filter papers by Exam Type.
- Admin selects Exam Type while uploading a paper.
- Existing papers are automatically treated as "अन्य" until edited/re-uploaded.


V3 CUSTOM SUBJECT:
- Subject is now a free-text field for both students and Admin.
- Suggested subjects include Physics, Chemistry, Mathematics, Biology, Economics, History, Geography, Political Science, Accountancy, Business Studies, English, Hindi, Science, Social Science and Computer Science.
- Users can type any other subject name manually.
- No database migration is required for this change.


V4 CUSTOM YEAR:
- Student Year filter is now a free-entry number field.
- Empty Year means All Years.
- Admin Year remains directly editable.
- No database migration is required.
