import 'package:flutter/material.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        Text(
          '關於本 App',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 12),
        Text(
          '此 App 用於英文單字學習，依照艾賓浩斯遺忘曲線安排複習，'
          '幫助你在關鍵時間點重複記憶。',
        ),
        SizedBox(height: 16),
        Text(
          '艾賓浩斯遺忘曲線說明',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 8),
        Text(
          '人在學習新資訊後，若不複習，記憶會隨時間快速下降。'
          '因此本 App 將複習安排在：第 1、2、3、5、7、12、19、31 天。',
        ),
        SizedBox(height: 16),
        Text(
          '使用方式',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 8),
        Text('1. 新增單字、例句與圖片。'),
        Text('2. 每天打開 App 查看今日複習清單。'),
        Text('3. 完成複習後點選「完成複習」。'),
      ],
    );
  }
}
