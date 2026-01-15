# Podfile for TryAngle iOS App
platform :ios, '15.1'

project 'TryAngleApp/TryAngleApp.xcodeproj'

target 'TryAngleApp' do
  use_frameworks!

  # ONNX Runtime Full version for RTMPose (모든 연산자 지원)
  # Mobile 버전이 아닌 전체 버전 사용 - 최신 버전
  pod 'onnxruntime-objc', '~> 1.23.0'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.1'
      # ONNX Runtime 헤더 경고 무시
      config.build_settings['CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER'] = 'NO'

      # Xcode 권장 설정 적용
      config.build_settings['CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING'] = 'YES'
      config.build_settings['CLANG_WARN_BOOL_CONVERSION'] = 'YES'
      config.build_settings['CLANG_WARN_COMMA'] = 'YES'
      config.build_settings['CLANG_WARN_CONSTANT_CONVERSION'] = 'YES'
      config.build_settings['CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS'] = 'YES'
      config.build_settings['CLANG_WARN_EMPTY_BODY'] = 'YES'
      config.build_settings['CLANG_WARN_ENUM_CONVERSION'] = 'YES'
      config.build_settings['CLANG_WARN_INFINITE_RECURSION'] = 'YES'
      config.build_settings['CLANG_WARN_INT_CONVERSION'] = 'YES'
      config.build_settings['CLANG_WARN_NON_LITERAL_NULL_CONVERSION'] = 'YES'
      config.build_settings['CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF'] = 'YES'
      config.build_settings['CLANG_WARN_OBJC_LITERAL_CONVERSION'] = 'YES'
      config.build_settings['CLANG_WARN_RANGE_LOOP_ANALYSIS'] = 'YES'
      config.build_settings['CLANG_WARN_STRICT_PROTOTYPES'] = 'YES'
      config.build_settings['CLANG_WARN_SUSPICIOUS_MOVE'] = 'YES'
      config.build_settings['CLANG_WARN_UNREACHABLE_CODE'] = 'YES'
      config.build_settings['CLANG_WARN__DUPLICATE_METHOD_MATCH'] = 'YES'
      config.build_settings['ENABLE_STRICT_OBJC_MSGSEND'] = 'YES'
      config.build_settings['GCC_NO_COMMON_BLOCKS'] = 'YES'
      config.build_settings['GCC_WARN_64_TO_32_BIT_CONVERSION'] = 'YES'
      config.build_settings['GCC_WARN_ABOUT_RETURN_TYPE'] = 'YES'
      config.build_settings['GCC_WARN_UNDECLARED_SELECTOR'] = 'YES'
      config.build_settings['GCC_WARN_UNINITIALIZED_AUTOS'] = 'YES'
      config.build_settings['GCC_WARN_UNUSED_FUNCTION'] = 'YES'
      config.build_settings['GCC_WARN_UNUSED_VARIABLE'] = 'YES'
    end
  end
end
