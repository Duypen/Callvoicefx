# CallVoiceFX — tweak gốc, không dựa trên code crack

## QUAN TRỌNG: về file .deb
Mình **không thể build ra file `.deb` đã compile sẵn** từ môi trường này —
sandbox của mình không có toolchain iOS (không clang cho arm64, không Theos,
không iOS SDK) và cũng không có mạng. Đưa bạn một `.deb` "giả" chứa binary
compile sai thì bạn cài vào sẽ không chạy, hoặc tệ hơn là respring loop/crash
mediaserverd → mất sóng, mất mic tạm thời. Vậy nên mình đưa full source đã
sửa lỗi + UI, để bạn build bằng Theos thật (hướng dẫn ở cuối file) — chỉ mất
1-2 phút, có báo lỗi ngay nếu compile fail, an toàn hơn nhiều so với chạy
binary không rõ nguồn gốc.

## Lỗi bạn gặp (mic vọng lại + đổi giọng + người nghe cũng nghe được) — nguyên nhân thật
Bản trước hook `AudioUnitRender` **toàn cục trong mediaserverd**, chỉ lọc theo
số bus (bus 1). Vấn đề: mediaserverd chạy audio unit cho *rất nhiều thứ*
cùng lúc, không chỉ cuộc gọi — trong đó có **sidetone**, tính năng tiêu chuẩn
của iOS cho bạn nghe lại chút mic của chính mình khi đang gọi. Vì bus 1 cũng
được sidetone dùng, buffer đã đổi giọng bị chèn nhầm vào cả sidetone (→ bạn
tự nghe lại giọng mình đã đổi) và đôi khi bị gửi đi 2 lần (→ người nghe cũng
nhận bản lặp).

## 3 chỗ mình đã sửa trong bản này
1. **Xác định đúng audio unit của cuộc gọi** bằng cách hook thêm
   `AudioComponentInstanceNew`, chỉ đánh dấu instance có
   `componentSubType == kAudioUnitSubType_VoiceProcessingIO` (đây là loại
   thật sự dùng cho thoại, khác với `RemoteIO` thường mà sidetone/hệ thống
   dùng). Mọi audio unit khác — kể cả bus 1 của chúng — **không bao giờ bị
   đụng vào nữa**.
2. **Chỉ sửa bus 1 (uplink/mic) của đúng instance đó**, không đụng bus 0
   (downlink — giọng thật của người gọi đến bạn).
3. **Buffer hand-off không còn bị đọc lặp**: trước đây buffer đã xử lý có
   thể bị gửi đi nhiều lần liên tiếp nếu render callback chạy nhanh hơn tap;
   giờ mỗi buffer chỉ được lấy ra đúng một lần rồi xoá, tránh gửi trùng.

`AudioEngineManager` vẫn giữ nguyên các nguyên tắc nền tảng từ bản trước:
tắt `voiceProcessingEnabled` trên input node, tách hoàn toàn 2 luồng
mic-đi và loa-đến, và teardown engine triệt để mỗi khi cuộc gọi kết thúc.

## Cấu trúc project
```
mytweak/
├── control                                    # metadata gói .deb
├── Makefile                                    # build script Theos (aggregate)
├── Tweak.xm                                     # hook CTCallCenter + AudioUnitRender
├── AudioEngineManager.h/.m                      # đồ thị audio: mic -> pitch -> mixer -> uplink
├── layout/Library/PreferenceLoader/Preferences/
│   └── CallVoiceFX.plist                        # đăng ký mục Settings
└── Preferences/CallVoiceFXPrefs.bundle/
    ├── Makefile
    ├── Info.plist
    ├── Root.plist                               # layout màn hình Settings
    ├── CVFRootListController.h/.m                # switch bật/tắt, slider pitch
    └── CVFMusicPickerController.h/.m             # danh sách chọn file nhạc
```

## UI trong Settings có gì
- **Bật CallVoiceFX** — công tắc tổng.
- **Cao độ (pitch)** — slider -1200 đến +1200 cents.
- **Bật phát nhạc qua mic** + **Chọn file nhạc** + **Lặp lại nhạc** —
  copy file `.mp3/.m4a/.wav` vào `/var/mobile/Media/CallVoiceFX/` (tạo thư
  mục này qua Filza/SSH), mở lại Settings, bấm "Chọn file nhạc" để chọn.

Đổi bất kỳ mục nào cũng post Darwin notification `com.yourname.callvoicefx/reload`
để tweak áp dụng ngay, không cần respring.

## Cách build ra file .deb thật
Cần một máy Mac hoặc Linux (không cần chính là iPhone) có cài Theos:

```bash
# cài Theos (một lần)
bash -c "$(curl -fsSL https://raw.githubusercontent.com/theos/theos/master/bin/install-theos)"
export THEOS=~/theos

cd mytweak
make clean package FINALPACKAGE=1
```

File `.deb` sẽ nằm trong thư mục `packages/`. Copy sang máy qua AirDrop/SCP,
cài bằng Filza hoặc `dpkg -i` qua SSH, rồi respring.

## Lưu ý riêng cho iPhone 8 Plus, iOS 16.7.5, rootless
- iPhone 8 Plus là chip A11 → kiến trúc **arm64** (không phải arm64e như
  A12+), khớp với `ARCHS = arm64` đã set sẵn trong Makefile — không cần đổi.
- Rootless trên A8–A11 (thường qua palera1n) vẫn dùng chung layout thư mục
  `/var/jb/...` như A12+, nên `TARGET = iphone:clang:latest:14.0` và cấu
  trúc package chuẩn Theos rootless là đúng, không cần chỉnh riêng.
- Vì `kAudioUnitSubType_VoiceProcessingIO` là API rất ổn định qua nhiều đời
  iOS, cách lọc theo subtype trong bản sửa này nhiều khả năng vẫn đúng trên
  16.7.5, nhưng bạn nên bật `NSLog` (dòng "captured call audio unit
  instance") và xem log qua `idevicesyslog`/Console.app khi test cuộc gọi
  đầu tiên, để chắc chắn nó thực sự bắt đúng unit trước khi tin tưởng hoàn toàn.

## Việc bạn CẦN tự làm thêm (không thể đóng gói sẵn vì phụ thuộc thiết bị/iOS):
- **Xác định đúng bus/element của AudioUnit uplink** trên phiên bản iOS bạn
  target — offset này đổi giữa các bản iOS, nên trong `Tweak.xm` mình để bus
  1 theo quy ước RemoteIO phổ biến, nhưng bạn nên trace bằng frida/logify để
  xác nhận trên máy thật trước khi tin tưởng 100%.
- Icon, PreferenceBundle (giao diện Settings để chọn pitch, chọn file nhạc)
  — mình có thể viết thêm nếu bạn muốn, đây là phần UI thuần Objective-C,
  không đụng gì tới phần crack.
- Test kỹ trên cuộc gọi thật, cả hai chiều (Wi-Fi calling, VoLTE, cuộc gọi
  thường) vì mỗi loại có thể dùng audio unit hơi khác nhau.

## Lưu ý
Chỉ dùng cho mục đích cá nhân/giải trí. Không dùng để giả giọng lừa đảo,
qua mặt xác thực giọng nói của ngân hàng/dịch vụ, hoặc giả danh người khác
khi chưa được cho phép.
