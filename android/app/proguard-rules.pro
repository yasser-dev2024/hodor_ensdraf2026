# PDFBox can optionally decode JPEG 2000 through a proprietary Gemalto
# decoder. The attendance importer extracts text only and never calls it.
-dontwarn com.gemalto.jp2.JP2Decoder
