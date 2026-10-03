import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppFonts {
  // Displays / títulos
  static TextStyle display({FontWeight weight = FontWeight.w700}) =>
      GoogleFonts.montserrat(fontWeight: weight);

  // Subtítulos / Botones
  static TextStyle subtitle({FontWeight weight = FontWeight.w400}) =>
      GoogleFonts.magra(fontWeight: weight);

  // Cuerpo de texto
  static TextStyle body({FontWeight weight = FontWeight.w400}) =>
      GoogleFonts.cambay(fontWeight: weight);
}
