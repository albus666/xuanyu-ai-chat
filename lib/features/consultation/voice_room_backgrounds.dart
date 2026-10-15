import 'package:flutter/material.dart';

const _officialVoiceRoomCoverPrefix = 'official://voice-room/';

class VoiceRoomOfficialBackground {
  const VoiceRoomOfficialBackground({
    required this.id,
    required this.name,
    required this.assetPath,
  });

  final String id;
  final String name;
  final String assetPath;

  String get coverValue => '$_officialVoiceRoomCoverPrefix$id';
}

const voiceRoomOfficialBackgrounds = <VoiceRoomOfficialBackground>[
  VoiceRoomOfficialBackground(
    id: 'star-sea-01',
    name: '星海晨光',
    assetPath: 'images/voice_room/backgrounds/star_sea_01.webp',
  ),
  VoiceRoomOfficialBackground(
    id: 'star-sea-02',
    name: '云上星河',
    assetPath: 'images/voice_room/backgrounds/star_sea_02.webp',
  ),
  VoiceRoomOfficialBackground(
    id: 'star-sea-03',
    name: '澄海幻想',
    assetPath: 'images/voice_room/backgrounds/star_sea_03.webp',
  ),
  VoiceRoomOfficialBackground(
    id: 'star-sea-04',
    name: '月湾流星',
    assetPath: 'images/voice_room/backgrounds/star_sea_04.webp',
  ),
];

/// 新建房间和未设置封面的旧房间统一使用较明亮的「澄海幻想」。
const voiceRoomDefaultBackground = VoiceRoomOfficialBackground(
  id: 'star-sea-03',
  name: '澄海幻想',
  assetPath: 'images/voice_room/backgrounds/star_sea_03.webp',
);

VoiceRoomOfficialBackground? voiceRoomOfficialBackground(String coverValue) {
  for (final background in voiceRoomOfficialBackgrounds) {
    if (background.coverValue == coverValue) return background;
  }
  return null;
}

ImageProvider<Object>? voiceRoomBackgroundImage(String coverValue) {
  final value = coverValue.trim();
  if (value.isEmpty) return null;
  final official = voiceRoomOfficialBackground(value);
  return official == null
      ? NetworkImage(value)
      : AssetImage(official.assetPath);
}

class VoiceRoomOfficialBackgroundPicker extends StatelessWidget {
  const VoiceRoomOfficialBackgroundPicker({
    super.key,
    required this.currentValue,
    required this.onSelected,
    this.dark = false,
  });

  final String currentValue;
  final ValueChanged<VoiceRoomOfficialBackground> onSelected;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final titleColor = dark ? Colors.white : const Color(0xFF173A3A);
    final hintColor = dark ? Colors.white54 : const Color(0xFF7F9290);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(
            '官方星海背景',
            style: TextStyle(
              color: titleColor,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          Text('点击即可切换', style: TextStyle(color: hintColor, fontSize: 10)),
        ]),
        const SizedBox(height: 10),
        SizedBox(
          height: 132,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: voiceRoomOfficialBackgrounds.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, index) {
              final item = voiceRoomOfficialBackgrounds[index];
              final selected = currentValue == item.coverValue;
              return InkWell(
                onTap: () => onSelected(item),
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 86,
                  child: Column(children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: selected
                                ? const Color(0xFF23C6C3)
                                : dark
                                    ? Colors.white24
                                    : const Color(0xFFDDE8E7),
                            width: selected ? 2.4 : 1,
                          ),
                          image: DecorationImage(
                            image: AssetImage(item.assetPath),
                            fit: BoxFit.cover,
                          ),
                        ),
                        child: selected
                            ? const Align(
                                alignment: Alignment.topRight,
                                child: Padding(
                                  padding: EdgeInsets.all(5),
                                  child: CircleAvatar(
                                    radius: 10,
                                    backgroundColor: Color(0xFF23C6C3),
                                    child: Icon(Icons.check_rounded,
                                        size: 14, color: Colors.white),
                                  ),
                                ),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: titleColor, fontSize: 10.5),
                    ),
                  ]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
