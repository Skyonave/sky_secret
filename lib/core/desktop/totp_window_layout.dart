import 'dart:ui';

const totpTileHeight = 56.0;
const totpTileWidth = 230.0;
const totpTileGap = 8.0;
const totpTileRadius = 10.0;
const totpWindowGap = 12.0;

int totpVisibleSlots(double height) => ((height + totpTileGap) / (totpTileHeight + totpTileGap)).floor();

List<Rect> totpTileRects(Size size) => [
  for (var index = 0; index < totpVisibleSlots(size.height); index++)
    Rect.fromLTWH(0, size.height - totpTileHeight - index * (totpTileHeight + totpTileGap), size.width, totpTileHeight),
];

Size totpWindowSize(Rect main, Rect work, {int count = 1}) {
  final bottom = main.bottom.clamp(work.top, work.bottom).toDouble();
  final available = totpVisibleSlots(bottom - work.top);
  final capacity = available < 1 ? 1 : available;
  final slots = count.clamp(1, capacity);
  return Size(totpTileWidth, slots * (totpTileHeight + totpTileGap) - totpTileGap);
}
