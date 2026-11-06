import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycoursera/models.dart';
import 'package:mycoursera/ui/widgets.dart';

void main() {
  testWidgets('skill status chip shows its label', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SkillStatusChip(SkillStatus.demonstrated))),
    );
    expect(find.text('Demonstrated'), findsOneWidget);
  });
}
