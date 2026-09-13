import 'package:flutter/scheduler.dart';

Future<void> prepareHiddenWindowFrame() {
  final binding = SchedulerBinding.instance;
  binding.scheduleWarmUpFrame();
  return binding.endOfFrame;
}
