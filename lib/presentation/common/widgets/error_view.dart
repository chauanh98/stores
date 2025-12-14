import 'package:flutter/material.dart';

class ErrorView extends StatelessWidget {
  final Object error;

  const ErrorView(this.error, {super.key});

  @override
  Widget build(BuildContext context) => Center(child: Text('$error'));
}
