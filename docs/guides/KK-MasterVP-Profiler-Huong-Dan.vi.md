# KK‑MasterVP Profiler — Hướng Dẫn Sử Dụng

Hướng dẫn thực tế, dễ hiểu cho người mới về cách đọc chỉ báo KK‑MasterVP Profiler trên MetaTrader 5, đã kiểm nghiệm kỹ lưỡng trên các cặp phổ biến như XAUUSD và BTCUSD.

Quan trọng — vui lòng đọc trước.Tài liệu này chỉ mang tính giáo dục và cung cấp thông tin. Đây không phải lời khuyên tài chính, không phải khuyến nghị đầu tư, và không phải lời mời mua hay bán bất kỳ sản phẩm nào. Profiler là một chỉ báo chỉ để hiển thị: nó vẽ bối cảnh lên màn hình và không đặt bất kỳ lệnh nào. Không có gì nó hiển thị là tín hiệu để bạn hành động theo. Giao dịch có rủi ro, bao gồm khả năng mất toàn bộ vốn. Diễn biến trong quá khứ và mọi dấu hiệu hiển thị trên biểu đồ đều mang tính lịch sử, không dự đoán kết quả tương lai. Bạn hoàn toàn chịu trách nhiệm cho quyết định của mình. Nếu còn băn khoăn, hãy tham khảo ý kiến chuyên gia được cấp phép.

## 1. Profiler là gì (trong một phút)



Profiler là một bảng quan sát chỉ để đọc, nằm phủ lên biểu đồ giá của bạn. Nó âm thầm tóm tắt hoạt động giao dịch đã tập trung ở đâu và dòng tiền gần đây đang nghiêng về phía nào, để bạn nhìn thấy cấu trúc thị trường trong nháy mắt thay vì phải nhìn chằm chằm vào những cây nến thô.

Nó làm ba việc:

Vẽ hồ sơ khối lượng (volume profile) — các đường ngang và một biểu đồ cột bên cạnh, đánh dấu những vùng giá nơi hoạt động diễn ra nhiều nhất.

Đọc dòng tiền gần đây — một bảng nhỏ gọn và một thẻ “nhận định” sát giá hiện tại, cho thấy bên mua hay bên bán đang sôi động hơn trong thời gian qua.

Minh hoạ các setup trong quá khứ — các dấu hiệu tuỳ chọn cho thấy một setup kiểu phá vỡ lẽ ra đã xuất hiện ở đâu trong quá khứ, hoàn toàn như một công cụ học tập.

Nó không phải: không phải robot giao dịch tự động, không phải dịch vụ tín hiệu, và không phải một lời hứa hẹn. Nó không bao giờ mở, sửa, hay đóng một vị thế nào. Hãy xem nó như một tấm bản đồ, không phải vô‑lăng.

## 2. Trước khi bắt đầu

Profiler được xây dựng để là bản sao trực quan của nghiên cứu KK‑MasterVP. Cài đặt mặc định của nó được tinh chỉnh cho XAUUSD (Vàng) trên khung M5 (5 phút).

Nó vẫn chạy được trên các cặp và khung thời gian khác, nhưng mặc định được chọn cho riêng tổ hợp trên. Ở nơi khác, hãy xem những gì hiển thị như một bản phác thảo sơ bộ hơn là một bức tranh hoàn chỉnh.

Nó chỉ để hiển thị. Việc gắn nó vào biểu đồ không thể đặt lệnh hay thay đổi tài khoản của bạn theo bất kỳ cách nào.

## 3. Cài đặt và gắn vào biểu đồ

Chép tệp KK-MasterVP-Profiler.ex5 vào thư mục MQL5/Indicators/ của MetaTrader 5 (hoặc thư mục con bạn dùng cho chỉ báo tuỳ chỉnh).

Khởi động lại MetaTrader 5, hoặc nhấp chuột phải vào danh sách Navigator → Indicators và chọn Refresh.

Mở biểu đồ XAUUSD, M5.

Kéo KK‑MasterVP‑Profiler từ Navigator thả vào biểu đồ, hoặc nhấp đúp vào nó.

Trong cửa sổ cài đặt, giữ nguyên các giá trị mặc định cho tổ hợp dự kiến, rồi nhấn OK.

Biểu đồ sẽ vẽ lại với hồ sơ khối lượng, bảng thông tin và các đường phủ. Mặc định một giao diện tối gọn gàng được áp dụng để mọi thứ dễ đọc; bạn có thể tắt nó đi (xem §7).

## 4. Tổng quan biểu đồ

Sau khi gắn, bạn có thể thấy các thành phần sau. Mỗi thành phần đều có thể bật/tắt trong phần cài đặt.

Trên màn hình

Đó là gì

Biểu đồ cột bên cạnh

Các thanh ngang cho thấy hoạt động tập trung ở đâu. Thanh càng dài = hoạt động tại mức giá đó càng nhiều. Một lát màu sáng hơn gợi ý xu hướng mua/bán gần đây.

mPOC / mVAH / mVAL

Ba đường của hồ sơ chính (master): mức giá sôi động nhất (POC) và hai biên trên/dưới của vùng hoạt động cốt lõi (VAH/VAL).

lPOC / lVAH / lVAL

Ba đường tương tự cho hồ sơ cục bộ (gần đây). Vẽ mờ và được gắn nhãn là bối cảnh phụ.

pPOC

Phiên bản dự đoán của mức giá sôi động nhất — bản xem trước hướng mà trung tâm hoạt động có thể trôi tới.

Thẻ Net / over / under

Nhận định sát giá, nằm cạnh giá hiện tại: bên nào sôi động hơn ngay quanh mức giá đó.

Bảng thông tin

Một thẻ nhỏ gọn (mặc định ở góc trên bên phải) với các chỉ số mô tả ở §6.

Lớp phủ EMA

Bốn đường trung bình động cùng một dải tô tuỳ chọn, để xem bối cảnh xu hướng.

Dấu hiệu setup

Các đường tuỳ chọn E / SL / TP1 / TP2 kèm nhãn WON / LOST / BE, cho thấy các setup trong quá khứ đã kết thúc ra sao.

Đường tham chiếu

Các đường mảnh cách giá hiện tại một khoảng cố định ở trên và dưới, như một thước đo trực quan.

## 5. Ý tưởng cốt lõi: hồ sơ và ba đường

Bạn không cần bất kỳ phép toán nào để dùng Profiler. Hai ý tưởng đơn giản mang lại phần lớn giá trị:

POC (Điểm kiểm soát) — mức giá duy nhất nơi hoạt động diễn ra nhiều nhất. Giá thường có xu hướng quay về quanh nó, nên đây là mức đáng theo dõi.

Vùng giá trị (VAH–VAL) — dải bao quanh POC chứa phần lớn hoạt động. VAH là biên trên, VAL là biên dưới. Giá dành phần lớn thời gian bên trong dải này và thường hành xử khác đi khi đẩy ra bên ngoài nó.

Profiler vẽ hai hồ sơ:

Hồ sơ chính (mPOC / mVAH / mVAL) — bức tranh rộng hơn, chậm hơn. Đây là cấu trúc tổng thể của bạn: những mức đã có ý nghĩa trong một quãng giao dịch đáng kể.

Hồ sơ cục bộ (lPOC / lVAH / lVAL) — bức tranh gần đây, nhanh hơn. Đây là bối cảnh cho thời điểm hiện tại.

Một cách đọc điềm tĩnh và phổ biến: các đường chính cho biết những “thềm” và “trần” quan trọng; các đường cục bộ cùng giá hiện tại cho biết bạn đang ở đâu so với chúng. Chỉ vậy thôi — không vội vã, không cần dự đoán.

Cách đo đạc và xác định kích thước của các hồ sơ là một phần trong thiết kế nội bộ của nghiên cứu và được chủ ý không trình bày ở đây. Bạn không cần đến nó để đọc biểu đồ.

## 6. Bảng thông tin (góc trên bên phải)

Bảng là một thẻ nhỏ tự cập nhật theo thị trường. Đọc từ trên xuống; mỗi dòng là một trạng thái mô tả, không phải một mệnh lệnh.

Nguồn dữ liệu (Feed) — cho biết Profiler đang dùng luồng tick chi tiết (TICK) hay phương án dự phòng theo nến (BAR fallback). Cả hai đều dùng được; BAR fallback chỉ nghĩa là lịch sử tick chi tiết không có sẵn nên một vài chỉ số mang tính xấp xỉ.

Net (đa khung thời gian) — đọc nhanh xu hướng mua/bán gần đây trên vài khung thời gian (ví dụ khung của biểu đồ cộng một khung lớn hơn), hiển thị dưới dạng phần trăm dương/âm. Dương nghiêng về bên mua, âm nghiêng về bên bán. Nó mô tả điều đã xảy ra gần đây, không phải điều sẽ xảy ra.

Độ biến động và độ trôi — một chỉ số gọn cho biết thị trường đang sôi động đến đâu, cùng với hướng mà trung tâm hoạt động đang trượt (lên, xuống, hay đi ngang). Dùng để ước lượng điều kiện đang yên ắng hay nhộn nhịp.

Độ ổn định của POC — mức giá sôi động nhất đang đứng yên (stable) hay đang dịch chuyển (rotation). Cấu trúc ổn định và cấu trúc đang trôi mang lại cảm giác giao dịch khác nhau.

Bias (xu hướng nghiêng) — một dòng tóm tắt độ nghiêng mà bảng đang đọc được, hoặc bias n/a khi chưa có hướng rõ ràng.

Sức khoẻ thực thi — chỉ số về spread và tốc độ khớp lệnh so với mức bình thường gần đây của chính chúng, hiển thị dưới dạng phần trăm (khoảng 100% = bình thường). Số càng cao, cùng các dấu cảnh báo ! / !!, nghĩa là điều kiện kém thuận lợi hơn thường lệ. Đây là một kiểm tra điều kiện, không phải tín hiệu giao dịch.

### Thẻ nhận định sát giá

Cạnh giá hiện tại bạn sẽ thấy một thẻ nhỏ với tối đa ba phần:

Net — độ nghiêng mua/bán tổng thể ngay quanh giá hiện tại.

over — độ nghiêng ngay phía trên giá.

under — độ nghiêng ngay phía dưới giá.

Một từ tiêu đề cũng có thể xuất hiện — ví dụ UP, DOWN, TREND UP / TREND DN, RANGE, hay POC rotation — như một bản tóm tắt mộc mạc về tính chất hiện tại của thị trường. Nó mang tính mô tả, không phải chỉ thị.

## 7. Lớp phủ EMA

Bốn đường trung bình động mang lại bối cảnh xu hướng cổ điển (nhãn hiển thị là EMA 25 / 75 / 100 / 200). Khi chúng xếp đúng thứ tự và giữ được sự sắp xếp đó, một dải mảnh tuỳ chọn sẽ tô giữa hai đường nhanh nhất để làm nổi bật một bối cảnh gọn gàng, một chiều. Khi các đường rối vào nhau, bối cảnh là hỗn hợp.

Lớp phủ này chỉ là bối cảnh — một cách để thấy nhanh liệu xu hướng rộng có đồng thuận hay mâu thuẫn với những gì hồ sơ và dòng tiền đang thể hiện. Bạn có thể ẩn toàn bộ chỉ bằng một công tắc.

## 8. Các dấu hiệu setup trong quá khứ

Nếu bật Show setups, Profiler sẽ vẽ các đường E (điểm vào), SL (mức dừng tham chiếu), TP1 và TP2 cho các setup kiểu phá vỡ mà nó nhận ra trong các nến lịch sử trên biểu đồ của bạn, và gắn nhãn mỗi setup là WON, LOST, hay BE (hoà vốn) dựa trên diễn biến giá sau đó.

Vui lòng đọc kỹ và điềm tĩnh:

Chúng là công cụ học tập. Chúng cho thấy các setup kiểu này đã kết thúc thế nào trong quá khứ trên biểu đồ này. Chúng không phải tín hiệu giao dịch trực tiếp, không phải lời khuyên, và không phải dự đoán rằng lần sau sẽ diễn ra tương tự.

Một chuỗi dài các nhãn WON không bảo đảm bất cứ điều gì. Thị trường thay đổi, và minh hoạ lịch sử không phải hiệu suất tương lai.

Con số phần trăm rủi ro hiển thị trên nhãn điểm vào chỉ là ước lượng để hiển thị. Nó không phải lời chỉ dẫn hãy mạo hiểm số tiền đó, và các mức tối thiểu, bước nhảy cùng giới hạn của sàn bạn vẫn được áp dụng.

Bạn cũng có thể bật dấu hiệu loại bỏ (rejection), chỉ ra những nơi một setup gần như đã hình thành nhưng bị lọc ra, kèm lý do ngắn như EMA opp (“dòng tiền nghiêng một hướng nhưng xu hướng lại không đồng thuận”) hay một ghi chú chase (đuổi giá). Chúng có mặt để giúp bạn hiểu logic, chỉ vậy thôi.

Một vài dấu hiệu hoà vốn tuỳ chọn và các công tắc liên quan tồn tại cho người tò mò; chúng chỉ thay đổi cách vẽ các dấu hiệu lịch sử và không bao giờ ảnh hưởng đến bất cứ thứ gì đang chạy thật.

## 9. Các tuỳ chọn cài đặt, diễn giải đơn giản

Bạn chỉ cần chạm vào vài công tắc. Cửa sổ cài đặt được chia nhóm; dưới đây là những mục đa số người dùng cần. (Nhiều núm tinh chỉnh chi tiết được chủ ý giữ gọn lại để danh sách ngắn gọn.)

Trade Setups (Setup giao dịch)

Show setups — vẽ các dấu hiệu lịch sử E/SL/TP1/TP2 (mặc định bật).

Show rejects — đánh dấu thêm các setup bị lọc ra, kèm lý do (mặc định tắt).

EMA filter — khi bật, một setup chỉ được hiển thị nếu các đường xu hướng đồng thuận với nó.

Volume Profile Core (Lõi hồ sơ khối lượng)

Hiện / ẩn hồ sơ — bật/tắt các đường hồ sơ chính, cục bộ và biểu đồ cột.

Use real ticks — mặc định tắt (hình ảnh ổn định hơn). Bật thì dùng luồng tick chi tiết để có cái nhìn mịn hơn, khi có sẵn.

Visuals (Hiển thị)

Các công tắc bật/tắt riêng cho đường chính, đường cục bộ, biểu đồ cột, đường dự đoán, bảng thông tin, thẻ nhận định, và dòng spread/tốc độ — để bạn chỉ giữ lại những gì thấy hữu ích.

EMA Overlay (Lớp phủ EMA)

Show EMAs và công tắc dải, cùng bốn độ dài nếu bạn thích tuỳ biến giao diện.

Chart Theme (Giao diện biểu đồ)

Apply theme — bộ màu tối gọn gàng. Tắt đi để giữ màu biểu đồ của riêng bạn.

Một số khoảng cách trên biểu đồ tự điều chỉnh theo mức độ sôi động của thị trường, nhờ vậy nét vẽ luôn hợp lý cả khi yên ắng lẫn nhộn nhịp. Bạn không cần phải quản lý điều đó.

## 10. Một cách dùng điềm tĩnh

Không có cách “đúng” duy nhất, và không điều nào dưới đây là lời khuyên — đây chỉ là cách bảng quan sát được thiết kế để đọc:

Bắt đầu từ cấu trúc. Ghi nhận giá đang nằm ở đâu so với POC chính và hai biên vùng giá trị. Bên trong dải, giữa hai biên, hay đang đẩy ra ngoài một biên?

Thêm dòng tiền. Liếc qua các chỉ số net trên bảng và thẻ nhận định sát giá. Bên mua hay bên bán có vẻ sôi động hơn, và điều đó có đồng thuận với cấu trúc không?

Kiểm tra lại xu hướng. Để lớp phủ EMA cho bạn biết bối cảnh rộng đang đồng thuận hay mâu thuẫn.

Lưu ý điều kiện. Nếu dòng sức khoẻ thực thi đang nhấp nháy ! hay !!, điều kiện đang gồ ghề hơn thường lệ — một lý do để kiên nhẫn, không phải vội vàng.

Dùng lịch sử để học, không phải như một lời hứa. Các dấu WON/LOST có mặt để xây dựng hiểu biết của bạn về phong cách này, không phải để đuổi theo cái tiếp theo.

Mục tiêu là sự rõ ràng và kiên nhẫn, không bao giờ là sự vội vã. Một công cụ như thế này hữu ích nhất khi nó giúp bạn chờ đợi những điều bạn hiểu — chứ không phải khi nó thúc bạn hành động.

## 11. Xử lý sự cố &amp; Câu hỏi thường gặp

Bảng hiển thị BAR fallback. Lịch sử tick chi tiết không có sẵn nên Profiler dùng nến thay thế. Điều này bình thường và ổn; các chỉ số chỉ kém mịn hơn một chút.

Không thấy dấu hiệu setup nào. Hoặc Show setups đang tắt, hoặc không có setup lịch sử đủ điều kiện trong vùng đang xem. Hãy cuộn về quá khứ, hoặc nới rộng phạm vi Profiler nhìn lại (trong cài đặt).

Thiếu các đường hoặc biểu đồ cột. Kiểm tra công tắc bật/tắt tương ứng trong Visuals. Nếu thiếu tất cả, có thể chỉ báo chưa được gắn, hoặc một chỉ báo khác đang vẽ đè lên.

Màu biểu đồ của tôi bị đổi. Đó là giao diện tích hợp. Tắt Apply theme để giữ màu của bạn.

Trông khác trên cặp/khung khác. Mặc định được tinh chỉnh cho XAUUSD M5. Ở nơi khác, hãy đọc nó như một bản xấp xỉ.

Nó có giao dịch hộ tôi không? Không. Nó chỉ để hiển thị và không bao giờ có thể đặt lệnh.

## 12. Thuật ngữ

POC — Point of Control: mức giá sôi động nhất.

Vùng giá trị (VAH / VAL) — dải chứa phần lớn hoạt động; VAH là biên trên, VAL là biên dưới.

Hồ sơ chính (master) — cấu trúc tổng thể, bức tranh rộng.

Hồ sơ cục bộ (local) — bối cảnh gần đây, ngắn hạn.

Net — độ nghiêng mua/bán gần đây (dương = bên mua, âm = bên bán).

POC dự đoán (pPOC) — bản xem trước hướng mà mức giá sôi động nhất có thể trôi tới.

WON / LOST / BE — kết quả của một setup lịch sử (thắng / thua / hoà vốn).

Sức khoẻ thực thi — đọc nhanh về spread và tốc độ khớp so với mức bình thường gần đây.

## 13. Tham chiếu nhanh các tham số cấu hình

Đây là bản đồ diễn giải đơn giản cho các công tắc bạn sẽ thấy trong cửa sổ cài
đặt của chỉ báo, được nhóm đúng như khi chúng xuất hiện. Phần này nhằm giúp bạn
học cách đọc biểu đồ — mang tính giáo dục, không phải lời khuyên tài chính, và
không giá trị nào ở đây là khuyến nghị giao dịch. Bản chất chỉ‑để‑hiển‑thị của
chỉ báo không hề thay đổi: không gì ở đây có thể đặt lệnh.

Mẹo: một preset dựng sẵn, **KK-MasterVP-Profiler.set**, đi kèm với chỉ báo. Trong
thẻ Inputs hãy nhấn **Load** và chọn nó để áp dụng một cấu hình XAUUSD M5 hợp lý
chỉ trong một bước, thay vì gõ tay từng giá trị.

Vài quy ước: **R** nghĩa là “đơn vị rủi ro” — một bội số của khoảng cách từ điểm
vào đến mức dừng tham chiếu (nên 0.8R là mục tiêu cách tám phần mười khoảng cách
đó). **ATR** là thước đo tiêu chuẩn cho biết giá thường dao động bao nhiêu; nhiều
khoảng cách được tính bằng bội số của ATR để nét vẽ luôn hợp lý dù thị trường yên
ắng hay nhộn nhịp.

### Trade Setups (Setup phá vỡ)

- **InpSetShow** — bật/tắt chính cho các dấu hiệu lịch sử E/SL/TP1/TP2. *Ví dụ:* BẬT để học cách các setup kiểu phá vỡ trong quá khứ đã kết thúc ra sao; TẮT để biểu đồ gọn gàng.
- **InpSetLookback** — số nến nhìn lại để quét các setup lịch sử. *Ví dụ:* 1800 quét khoảng 1800 nến gần nhất.
- **InpSetKeep** — số dấu hiệu tối đa giữ trên màn hình; cũ nhất sẽ rớt trước. *Ví dụ:* 12 giúp biểu đồ không bị rối.
- **InpSetTp1R** — khoảng cách mục tiêu thứ nhất, tính bằng R. *Ví dụ:* 0.8 đặt TP1 ở tám phần mười khoảng cách dừng.
- **InpSetTp2R** — khoảng cách mục tiêu thứ hai, tính bằng R. *Ví dụ:* 1.8 đặt TP2 ở gần gấp đôi khoảng cách dừng.
- **InpSetRiskPct** — một con số chỉ‑để‑hiển‑thị dùng để ước lượng khối lượng trên nhãn điểm vào. *Ví dụ:* 1.0 minh hoạ việc tính cỡ lệnh cho 1% số dư — không phải lệnh bảo bạn mạo hiểm số tiền đó, và các mức tối thiểu/bước/giới hạn của sàn vẫn áp dụng.
- **InpSetShowRejects** — đánh dấu thêm các tín hiệu bị lọc ra, kèm một nhãn lý do ngắn. *Ví dụ:* BẬT để hiểu vì sao một số ứng viên bị bỏ qua.
- **InpSetBeRatchet** — cơ chế dời về hoà vốn cho cách minh hoạ mức dừng của dấu hiệu. *Ví dụ:* TẮT cho thấy lịch sử TP1‑so‑với‑SL thuần; BẬT cho thấy mức dừng nhích về hoà vốn sau khi có tiến triển.
- **InpSetEmaFilter** — một bộ lọc đồng thuận xu hướng tuỳ chọn cho các setup được vẽ. *Ví dụ:* BẬT chỉ hiển thị các setup khớp với cụm EMA; TẮT hiển thị tất cả.

### Execution Health (Sức khoẻ thực thi)

- **InpShowExecRow** — dòng trên bảng so sánh spread và tốc độ khớp hiện tại với mức bình thường gần đây của chính chúng (khoảng 100% = bình thường). *Ví dụ:* BẬT để nhận ra khi điều kiện gồ ghề hơn thường lệ; đây là kiểm tra điều kiện, không phải tín hiệu.

### Visuals (Hiển thị)

- **InpShowMasterLines** — các đường POC/VAH/VAL chính.
- **InpShowLocalLines** — các đường POC/VAH/VAL cục bộ (gần đây).
- **InpShowHistogram** — biểu đồ cột hoạt động theo giá.
- **InpHistFront** — vẽ biểu đồ cột phía trước nến thay vì phía sau.
- **InpShowPredictedPoc** — đường xem trước POC dự đoán.
- **InpShowPanel** — thẻ thông tin nhỏ gọn ở góc trên bên phải.
- **InpShowVerdict** — thẻ nhận định sát giá.

### Volume Profile Core (Lõi hồ sơ khối lượng)

- **InpVpLookback** — độ dài, tính bằng số nến, của cửa sổ hồ sơ cục bộ (gần đây). *Ví dụ:* số càng lớn tóm tắt một quãng giao dịch càng dài.
- **InpMasterMult** — cửa sổ chính bằng cửa sổ cục bộ nhân với giá trị này. *Ví dụ:* với cửa sổ cục bộ 108 và hệ số 4, hồ sơ chính bao phủ 432 nến.
- **InpUseRealTicks** — TẮT (mặc định) dùng nguồn nến ổn định hơn; BẬT dùng luồng real‑tick chi tiết để có cái nhìn mịn hơn khi có sẵn.
- **InpHistTickDelta** — thêm một lớp màu theo dòng tiền gần đây vào biểu đồ cột từ hoạt động tick có dấu, trên nền các hàng ổn định. *Ví dụ:* BẬT để cảm nhận bên nào sôi động hơn gần đây.
- **InpHistRecency** — đặt trọng số cho hoạt động gần đây cao hơn hoạt động cũ. *Ví dụ:* BẬT khiến bức tranh nghiêng về điều vừa xảy ra.
- **InpHistNetScale** — co giãn lát màu xanh/đỏ theo mức mất cân bằng mạnh nhất để luôn nhìn rõ trên mọi khung thời gian.

### EMA Overlay (Lớp phủ EMA)

- **InpShowEmas** — vẽ bốn đường trung bình động.
- **InpEma1Len / InpEma2Len / InpEma4Len** — chu kỳ của đường nhanh, đường giữa và đường chậm. *Ví dụ:* số nhỏ phản ứng nhanh hơn nhưng dao động nhiều hơn; số lớn mượt hơn nhưng chậm hơn.
- **InpShowEmaZone** — dải tô mảnh giữa hai đường nhanh nhất khi cụm đường sắp xếp gọn gàng.

### Chart Theme (Giao diện biểu đồ)

- **InpApplyTheme** — áp dụng bộ màu tối gọn gàng khi gắn vào. *Ví dụ:* TẮT để giữ nguyên màu biểu đồ của bạn.

Một số giá trị tinh chỉnh sâu hơn được chủ ý giữ ở bên trong, để danh sách này
ngắn gọn và biểu đồ dễ đọc. Bạn không cần đến chúng để dùng tốt Profiler.

## 14. Tuyên bố miễn trừ trách nhiệm đầy đủ

Chỉ báo này và hướng dẫn này được cung cấp “nguyên trạng”, chỉ cho mục đích giáo dục và thông tin, không kèm bảo đảm dưới bất kỳ hình thức nào. Chúng không cấu thành lời khuyên tài chính, đầu tư, pháp lý hay thuế, và không được phép dựa vào như vậy. Không có kết quả nào được hứa hẹn hay bảo đảm. Các dấu hiệu, thống kê và chỉ số đều mang tính lịch sử hoặc mô tả và không phản ánh kết quả tương lai. Giao dịch các sản phẩm đòn bẩy mang rủi ro thua lỗ cao và không phù hợp với tất cả mọi người; bạn có thể mất nhiều hơn khả năng chịu đựng. Chỉ riêng bạn chịu trách nhiệm cho các quyết định của mình và hậu quả của chúng. Trước khi giao dịch, hãy cân nhắc tìm lời khuyên từ một chuyên gia độc lập, được cấp phép phù hợp. Bằng việc sử dụng chỉ báo này, bạn chấp nhận rằng các tác giả và đơn vị phân phối không chịu bất kỳ trách nhiệm pháp lý nào cho mọi tổn thất hay thiệt hại phát sinh từ việc sử dụng nó.

