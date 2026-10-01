import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';

void main() {
  testWidgets('ZenLog App loads landing flow smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ZenLogApp());
    expect(find.text('ZenLog'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
  });
}
