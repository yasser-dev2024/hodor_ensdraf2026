# PDFBox references Gemalto's optional JPEG 2000 decoder. The decoder is not
# bundled by read_pdf_text and PDFBox falls back when it is unavailable.
-dontwarn com.gemalto.jp2.**
