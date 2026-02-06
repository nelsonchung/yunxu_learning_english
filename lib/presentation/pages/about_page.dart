import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../widgets/section_card.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static final Future<String> _versionTextFuture = _loadVersionText();

  static Future<String> _loadVersionText() async {
    final info = await PackageInfo.fromPlatform();
    final build = info.buildNumber.trim();
    if (build.isEmpty) {
      return info.version;
    }
    return '${info.version}+${info.buildNumber}';
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom + 120.0;

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 20, 16, bottomPadding),
      children: [
        FutureBuilder<String>(
          future: _versionTextFuture,
          builder: (context, snapshot) {
            final version = snapshot.data ?? '讀取中...';
            return SectionCard(
              title: '關於本 App',
              subtitle: '用遺忘曲線建立穩定的英文記憶',
              child: Text(
                '此 App 用於英文單字學習，依照艾賓浩斯遺忘曲線安排複習，'
                '幫助你在關鍵時間點重複記憶。\n版本：$version',
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        const SectionCard(
          title: '艾賓浩斯遺忘曲線',
          subtitle: '記憶若不複習會快速下降',
          child: Text(
            '本 App 將複習安排在：第 1、2、3、5、8、13、21、39 天。'
            '透過固定節奏複習，逐步加深長期記憶。',
          ),
        ),
        const SizedBox(height: 16),
        const SectionCard(
          title: '使用方式',
          subtitle: '三個步驟開始複習',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('1. 新增單字、例句與圖片。'),
              SizedBox(height: 6),
              Text('2. 每天打開 App 查看今日複習清單。'),
              SizedBox(height: 6),
              Text('3. 完成複習後點選「完成複習」。'),
            ],
          ),
        ),
      ],
    );
  }
}
