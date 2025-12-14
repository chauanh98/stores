import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/customers/customers_providers.dart';
import '../../../domain/entities/customer.dart';

class AddCustomerPage extends ConsumerStatefulWidget {
  const AddCustomerPage({super.key});

  @override
  ConsumerState<AddCustomerPage> createState() => _AddCustomerPageState();
}

class _AddCustomerPageState extends ConsumerState<AddCustomerPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.addNewCustomer),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saving ? null : _save,
            tooltip: l10n.save,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                _field(_name, l10n.name, Icons.person),
                const SizedBox(height: 12),
                _field(_phone, l10n.phone, Icons.phone,
                    keyboard: TextInputType.phone),
                const SizedBox(height: 12),
                _field(_email, l10n.email, Icons.email,
                    keyboard: TextInputType.emailAddress, required: false),
                const SizedBox(height: 12),
                _field(_address, l10n.address, Icons.location_on,
                    maxLines: 2, required: false),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label,
    IconData icon, {
    TextInputType keyboard = TextInputType.text,
    int maxLines = 1,
    bool required = true,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final isNumber = keyboard == TextInputType.phone;

    return TextFormField(
      controller: c,
      maxLines: maxLines,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
      validator: (value) {
        final text = value?.trim() ?? '';

        if (required && text.isEmpty) {
          return '${l10n.pleaseEnter} $label';
        }

        if (isNumber && text.isNotEmpty) {
          final number = int.tryParse(text);
          if (number == null) {
            final vnPhoneRegex = RegExp(r'^(03|05|07|08|09)\d{8}$');
            if (!vnPhoneRegex.hasMatch(text)) {
              return l10n.pleaseEnterValidNumber;
            }
          }
        }

        if (keyboard == TextInputType.emailAddress && text.isNotEmpty) {
          final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
          if (!emailRegex.hasMatch(text)) {
            return l10n.pleaseEnterValidEmail;
          }
        }

        return null;
      },
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context)!;
    try {
      final customer = Customer(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        address: _address.text.trim(),
        purchases: const [],
      );
      await ref.read(customerRepositoryProvider).upsert(customer);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.added)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
