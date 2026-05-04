import 'package:flutter_test/flutter_test.dart';
import 'package:imu_navigator/main.dart';

void main() {
  testWidgets('shows the IMU Navigator home screen', (tester) async {
    await tester.pumpWidget(const IMUNavigatorApp());

    expect(find.text('IMU NAVIGATOR'), findsOneWidget);
  });
}
