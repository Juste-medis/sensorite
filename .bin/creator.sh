#!/bin/bash

mkdir -p lib/app/theme && \
mkdir -p lib/core/constants && \
mkdir -p lib/core/utils && \
mkdir -p lib/core/models && \
mkdir -p lib/data/repositories && \
mkdir -p lib/data/services && \
mkdir -p lib/domain/algorithms && \
mkdir -p lib/presentation/screens && \
mkdir -p lib/presentation/widgets/common && \
mkdir -p lib/presentation/widgets/sensors && \
mkdir -p lib/presentation/widgets/charts && \
mkdir -p lib/presentation/viewmodels && \
mkdir -p lib/di && \
touch lib/main.dart && \
touch lib/app/app.dart && \
touch lib/app/theme/app_theme.dart && \
touch lib/app/theme/colors.dart && \
touch lib/app/theme/text_styles.dart && \
touch lib/core/constants/app_strings.dart && \
touch lib/core/constants/sensor_constants.dart && \
touch lib/core/utils/file_helper.dart && \
touch lib/core/utils/timestamp_helper.dart && \
touch lib/core/utils/sensor_helper.dart && \
touch lib/core/models/sensor_data.dart && \
touch lib/core/models/imu_data.dart && \
touch lib/core/models/position.dart && \
touch lib/data/repositories/sensor_repository.dart && \
touch lib/data/services/sensor_service.dart && \
touch lib/data/services/file_service.dart && \
touch lib/data/services/fusion_service.dart && \
touch lib/domain/algorithms/madgwick.dart && \
touch lib/domain/algorithms/mahony.dart && \
touch lib/domain/algorithms/integrator.dart && \
touch lib/presentation/screens/home_screen.dart && \
touch lib/presentation/screens/record_screen.dart && \
touch lib/presentation/screens/visualize_screen.dart && \
touch lib/presentation/screens/settings_screen.dart && \
touch lib/presentation/widgets/common/notion_card.dart && \
touch lib/presentation/widgets/common/notion_button.dart && \
touch lib/presentation/widgets/common/notion_divider.dart && \
touch lib/presentation/widgets/common/notion_header.dart && \
touch lib/presentation/widgets/sensors/sensor_card.dart && \
touch lib/presentation/widgets/sensors/recording_indicator.dart && \
touch lib/presentation/widgets/sensors/trajectory_preview.dart && \
touch lib/presentation/widgets/charts/accelerometer_chart.dart && \
touch lib/presentation/widgets/charts/gyroscope_chart.dart && \
touch lib/presentation/widgets/charts/trajectory_chart.dart && \
touch lib/presentation/viewmodels/recording_viewmodel.dart && \
touch lib/presentation/viewmodels/sensor_viewmodel.dart && \
touch lib/presentation/viewmodels/settings_viewmodel.dart && \
touch lib/di/service_locator.dart && \
echo "Structure de projet créée avec succès."