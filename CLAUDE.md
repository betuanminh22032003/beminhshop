# StarCi Shop

@AGENTS.md

## Ghi chú riêng cho Claude Code

- Trước khi sửa một service, đọc `README.md` ở gốc repo — trách nhiệm và ranh giới của cả bốn service đã được khai báo sẵn, đừng suy đoán lại.
- Khi task thuộc milestone mới (container, database, gateway, saga, flash sale), tạo hạ tầng cắm vào các thư mục `services/` hiện có; không tái cấu trúc monorepo trừ khi người dùng yêu cầu rõ ràng.
- Môi trường Windows: shell chính là PowerShell. `dotnet` CLI chạy được từ cả PowerShell lẫn Bash tool trong session này (.NET SDK 10.0.301 đã cài, kèm 6.0.428).
- .NET SDK có nhiều bản trên máy (6.0.428 và 10.0.301) — các project ở đây target `net10.0`; đừng hạ TargetFramework trừ khi có lý do rõ ràng.
