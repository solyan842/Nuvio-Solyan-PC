# Nuvio-SolYan-PC libmpv Fix v1.0.0

Bản stable cho lỗi Nuvio Desktop Windows + SFilm3/VSMOV series:
mở tập phim nhưng player nhảy thẳng tới cuối timeline rồi auto-next liên tục.

## Nguyên nhân đã xác nhận bằng A/B

Không phải SFilm3, không phải HTTP headers, không phải resume và không phải auto-next.
Nguyên nhân nằm ở Windows libmpv runtime cũ mà Nuvio đang bundle.

Known-bad Nuvio libmpv SHA256:
07c68bb211f23a218ded0a36eb12207dc3aeb44e5318ffca6ce9dcc7c3173906

Fixed libmpv SHA256:
361e3a306707454a24e7d3558b2eb7a9ccc23a4f5ed396fe7e77f0a44908eda5

Nguồn fixed runtime:
Predidit/media-kit Windows libmpv release 202609151348
mpv-dev-x86_64-20260915-git-0b7ed67.7z
Archive SHA256:
8adceab30b6bcc5503fa9d3823b68f4acd15ee1c41d6dc2492826f373531c10a

## Dùng hằng ngày

Sau mỗi lần Nuvio cập nhật:
1. Đóng Nuvio.
2. Chạy STATUS.cmd.
3. Nếu STATUS = NEEDS_PATCH, chạy APPLY.cmd.
4. Mở lại Nuvio.

Các trạng thái:
- PATCHED: đã có runtime sửa lỗi, không cần làm gì.
- NEEDS_PATCH: Nuvio vẫn dùng runtime cũ gây lỗi; APPLY.cmd sẽ patch.
- UPSTREAM_CHANGED: Nuvio đã thay libmpv mới; patch KHÔNG tự ghi đè. Cần kiểm runtime mới trước.
- OLD_AB_BRIDGE_ACTIVE: còn một patch A/B cũ ở player_bridge; rollback A/B cũ trước.

## An toàn

APPLY:
- chỉ patch khi libmpv hiện tại đúng SHA known-bad;
- không ghi đè runtime mới lạ của upstream;
- không chồng lên A/B header/resume cũ;
- backup nguyên JAR theo SHA của từng phiên bản Nuvio;
- kiểm SHA backup trước khi sửa;
- chỉ thay native/windows/libmpv-2.dll;
- kiểm SHA DLL sau khi patch;
- lưu rollback state cả cạnh bộ patch và cạnh JAR.

ROLLBACK:
- chỉ rollback khi JAR hiện tại đúng SHA của bản đã patch;
- nếu Nuvio đã cập nhật JAR sau đó, rollback sẽ từ chối để không kéo app mới về bản cũ;
- backup gốc được giữ lại.

## Nâng cấp từ A/B #3

Nếu A/B runtime #3 đang hoạt động, chạy APPLY.cmd của bản stable này.
Script sẽ nhận thấy fixed libmpv đã có, tìm backup A/B cũ, tạo stable rollback state và chuyển sang trạng thái stable mà không sửa lại binary.
