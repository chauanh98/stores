import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/main.dart';
import 'package:stores/presentation/auth/pages/login_page.dart';

class FakeAuthNotifier extends StateNotifier<UserAccount?>
    implements AuthNotifier {
  FakeAuthNotifier(super.state);

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    state = null;
  }
}

void main() {
  testWidgets('Renders LoginPage when not authenticated',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authLoadingProvider.overrideWith((ref) => false),
          authProvider.overrideWith((ref) => FakeAuthNotifier(null)),
        ],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LoginPage), findsOneWidget);
  });
}
