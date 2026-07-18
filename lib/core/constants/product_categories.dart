import 'package:flutter/material.dart';

class ProductCategories {
  static const List<String> categories = [
    'Smartphone',
    'Laptop',
    'Tablet',
    'Desktop',
    'Monitor',
    'Keyboard',
    'Mouse',
    'Headphone',
    'Speaker',
    'Camera',
    'Accessories',
    'Other',
  ];

  static IconData getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'smartphone':
        return Icons.phone_android;
      case 'laptop':
        return Icons.laptop;
      case 'tablet':
        return Icons.tablet;
      case 'desktop':
        return Icons.desktop_windows;
      case 'monitor':
        return Icons.monitor;
      case 'keyboard':
        return Icons.keyboard;
      case 'mouse':
        return Icons.mouse;
      case 'headphone':
        return Icons.headphones;
      case 'speaker':
        return Icons.speaker;
      case 'camera':
        return Icons.camera_alt;
      case 'accessories':
        return Icons.cable;
      default:
        return Icons.devices_other;
    }
  }
}
