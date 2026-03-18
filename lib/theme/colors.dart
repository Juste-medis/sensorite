import 'package:flutter/material.dart';

class AppColors {
  // ===== THÈME CLAIR =====
  // Neutres (inspiré de Notion)
  static const Color background = Color(0xFFF7F7F7); // Fond principal
  static const Color surface = Color(0xFFFFFFFF); // Cartes/surfaces
  static const Color border = Color(0xFFE5E5E5); // Bordures légères

  // Texte
  static const Color textPrimary = Color(0xFF37352F); // Texte principal
  static const Color textSecondary = Color(0xFF6B6B6B); // Texte secondaire
  static const Color textPlaceholder = Color(0xFFB3B3B3); // Placeholder

  // Accents (minimalistes)
  static const Color accentBlue = Color(0xFF0B6B99); // Boutons principaux
  static const Color accentGreen = Color(0xFF0F7B6B); // Succès/enregistrement
  static const Color accentRed = Color(0xFFE03E3E); // Arrêt/erreur
  static const Color accentGray = Color(0xFF787774); // Actions secondaires

  // États
  static const Color hover = Color(0xFFEFEFEF); // Survol/sélection
  static const Color disabled = Color(0xFFF0F0F0); // Désactivé

  // ===== THÈME SOMBRE =====
  // Neutres
  static const Color darkBackground = Color(0xFF121212); // Fond principal
  static const Color darkSurface = Color(0xFF1E1E1E); // Cartes/surfaces
  static const Color darkBorder = Color(0xFF363636); // Bordures légères

  // Texte
  static const Color darkTextPrimary = Color(0xFFEDEDED); // Texte principal
  static const Color darkTextSecondary = Color(0xFFB3B3B3); // Texte secondaire
  static const Color darkTextPlaceholder = Color(0xFF757575); // Placeholder

  // Accents (identiques au thème clair pour la cohérence)
  static const Color darkAccentBlue = Color(
    0xFF1E88E5,
  ); // Boutons principaux (plus lumineux)
  static const Color darkAccentGreen = Color(
    0xFF26A69A,
  ); // Succès/enregistrement
  static const Color darkAccentRed = Color(0xFFE74C3C); // Arrêt/erreur
  static const Color darkAccentGray = Color(0xFF9E9E9E); // Actions secondaires

  // États
  static const Color darkHover = Color(0xFF2E2E2E); // Survol/sélection
  static const Color darkDisabled = Color(0xFF1A1A1A); // Désactivé
}
