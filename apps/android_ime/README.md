# android_ime — Bộ gõ Bow Go cho Android (chưa làm)

Bộ gõ trên Android là một **`InputMethodService`** viết bằng **Kotlin/Java**. Đây là
API Android cho bàn phím ảo / bộ gõ; nó hiển thị bàn phím và đẩy ký tự vào ô nhập của
ứng dụng đang focus. Flutter chạy trong cửa sổ app riêng nên không đóng vai trò này.

## Cách phần này dùng lại engine
- Logic gõ (Telex/VNI, đặt dấu) là **spec chung** ở [`packages/viet_engine`](../../packages/viet_engine).
- **Không port engine sang Kotlin**: dùng lại engine C++ ở
  [`apps/windows_ime/engine`](../windows_ime/engine) qua NDK/JNI (xem
  [ADR 0001](../../docs/adr/0001-engine-core-dung-chung.md)). Engine đó đã chạy
  [bộ ca chuẩn dùng chung](../../packages/viet_engine/spec/typing_cases.tsv).

## Việc cần làm khi bắt đầu
- [ ] Dựng skeleton `InputMethodService` + layout bàn phím
- [ ] Khai báo bộ gõ trong AndroidManifest (`android.view.InputMethod`)
- [ ] Build engine C++ cho Android (CMake + NDK) và bọc JNI cho `InputMethodService`
