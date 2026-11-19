import 'package:chainvault/core/address_book.dart';
import 'package:chainvault/features/address_book/address_book_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('Address book saves, edits and reloads contacts', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const ShadApp(home: Scaffold(body: AddressBookPage())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('＋ 添加地址'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    expect(find.text('请输入名称'), findsOneWidget);
    await tester.enterText(
      find
          .descendant(
            of: find.byType(ShadDialog),
            matching: find.byType(EditableText),
          )
          .first,
      '收款人',
    );
    await tester.enterText(
      find
          .descendant(
            of: find.byType(ShadDialog),
            matching: find.byType(EditableText),
          )
          .last,
      'TMVQGm1qAQYVdetCeGRRkTWYYrLXuHK2HC',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    expect(find.text('收款人'), findsOneWidget);
    expect((await AddressBookRepository().load()).single.chain.name, 'TRON');
    await tester.tap(find.text('修改'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find
          .descendant(
            of: find.byType(ShadDialog),
            matching: find.byType(EditableText),
          )
          .first,
      '新名称',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
    expect((await AddressBookRepository().load()).single.name, '新名称');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      const ShadApp(home: Scaffold(body: AddressBookPage())),
    );
    await tester.pumpAndSettle();
    expect(find.text('新名称'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ShadButton, '删除').last);
    await tester.pumpAndSettle();
    expect(await AddressBookRepository().load(), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
