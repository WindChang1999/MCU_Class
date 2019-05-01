B_2ms BIT 01H            ;; 2ms定时器标志
OP_B  BIT  02H           ;; 标志当前OPERATOR中是否有运算符存在, 为1则认为OPERATOR有效, 为0则认为当前无运算符
NUM2_BEGIN  BIT  03H     ;; 表示第二个运算数是否已经开始输入, 为1表示第二个数已经开始输入, 为0表示第二个数还未输入
B_DISPLAY   BIT  04H     ;; 0则不显示, 1则LED显示
B_EQU       BIT  05H     ;; 等号是否被按下标志

MUL1_BIT    BIT 0AH      ;; 被乘数符号位保存
MUL2_BIT    BIT 0BH      ;; 乘数符号位保存


LED_BUF EQU 24H          ;; 显示缓存区的最低地址         30H OR 38H
P_BCDDISP EQU 25H

KEYCODE EQU 28H          ;; 按键值
LASTCODE EQU 29H
N_SAME   EQU 2AH         ;; KEY_STATE
N_DISP   EQU 2BH         ;; DISP_STATE, 在每个时间片中显示第几位数
THERSHORD EQU 2CH        ;; 检测按键 N_SAME 的阈值


N_LENGTH  EQU 2DH        ;; DISPLAY 指示显示的长度 1~8
N_POINT   EQU 2EH        ;; DISPLAY 指示小数点的位置, 当N_POINT >= N_LENGTH时不显示小数点    0~7
OPERATOR  EQU 2FH        ;; 0->+, 1->-, 2->*, 3->/, 0FFH->无操作符状态

NUM1_HEAD EQU 40H               ;; 运算数1最低字节地址 40H
NUM1_TAIL EQU 43H
BCD1_HEAD EQU 44H               ;; 运算数1 ---- BCD码
NUM2_HEAD EQU 48H               ;; 运算数2最低字节地址 48H
NUM2_TAIL EQU 47H
BCD2_HEAD EQU 4CH               ;; 运算数2 ---- BCD码

SHIFT_4BIT_P EQU 58H            ;; 多字节带C左右移最低字节地址
SHIFT_N      EQU 59H            ;; 多字节左右移数据长度

CLEAR_MEM_HEAD EQU 5AH          ;; CLEAR_MEM 函数 用于清0一块内存区, 最低字节地址
CLEAR_MEM_N    EQU 5BH          ;; CLEAR_MEM 函数 数据长度
BIN_AREA       EQU 5CH          ;; BIN二进制区 = BCD码区-4
BCD_AREA       EQU 5DH          ;; BCD码区

SIGNED_BIT_HEAD  EQU 5EH        ;; SAVE_SIGNED 函数操作数
SIGNED_BIT  BIT 0CH             ;; SAVE_SIGNED函数用于提取一个4字节数的符号位

MUL_L          EQU 50H          ;; 乘积低4字节     58H~5FH
MUL_H          EQU 54H          ;; 乘积高4字节

BUMA_HEAD      EQU 5FH          ;; 4字节补码最低字节地址
BUMA_SIGNED    BIT 09H          ;; 求补码时用于保存符号位

DIVIDEND_HEAD  EQU 60H          ;; 被除数4字节 60H~63H
REMAINDER_HEAD EQU 64H          ;; 余数4字节 64H~67H
DIVISOR_HEAD   EQU 48H          ;; 除数4字节      ==     NUM2_HEAD
ZERO_ERROR_BIT BIT 0DH          ;; 除数为0错误标志

FLOAT_N        EQU 68H          ;; 转换小数位数长度
MOV_HEAD_1     EQU 69H          ;; MOV_4BIT: 源数据区最低字节地址
MOV_HEAD_2     EQU 6AH          ;; MOV_4BIT: 目的数据区最低字节地址
MOV_N          EQU 6BH          ;; MOV_4BIT: 数据长度


ORG 0000H
   LJMP INIT
ORG 000BH
LJMP TIMER0_INT
ORG 0100H
INIT:
    MOV     SP, #0E0H
    MOV     TMOD,#01H              ;;TIMER0 MODE1
    MOV     TCON,#0
    MOV     TH0,#0F8H
    MOV     TL0,#30H               ;;2mS
    MOV     KEYCODE,  #0FFH
    MOV     LASTCODE, #0FFH
    MOV     THERSHORD, #15        ;; N_SAME的阈值
    MOV     N_SAME, #0
    MOV     N_DISP, #0
    MOV     N_LENGTH, #0
    MOV     N_POINT,  #9
    MOV     OPERATOR, #0FFH
    MOV     LED_BUF, #30H
    CLR     OP_B
    CLR     NUM2_BEGIN
    CLR     B_EQU
    SETB    B_DISPLAY
    SETB    TR0
    SETB    ET0
    SETB    EA
    MOV     CLEAR_MEM_HEAD, LED_BUF                   ;; 清显示缓存区     30H~3FH
    MOV     CLEAR_MEM_N, #16
    LCALL   CLEAR_MEM
    MOV     CLEAR_MEM_HEAD, #NUM1_HEAD                ;; 清操作数区       40H~4FH
    MOV     CLEAR_MEM_N, #16
    LCALL   CLEAR_MEM

;; -------------------------------------
;; 主循环部分
;; -------------------------------------
MAIN_LOOP:
    LCALL   KEY_SCAN
    LCALL   DO_KEY_NUMBER
    LCALL   DO_KEY_BACKSPACE
    LCALL   DO_KEY_OP
    LCALL   DO_KEY_EQU
    LCALL   CAL_ADD_SUBB
    LCALL   CAL_MUL
    LCALL   CAL_DIV
    LCALL   DISPLAY
    JNB     B_2ms, $
    CLR     B_2ms
    SJMP    MAIN_LOOP


;; -----------------------------------------------
;; 2ms定时器中断复位
;; INPUT: NONE
;; OUTPUT: NONE
;; INFLUENCE: B_2ms
;; -----------------------------------------------
TIMER0_INT:
    MOV     TH0, #0F8H
    MOV     TL0, #30H
    SETB    B_2ms
    RETI


;; --------------------------------------------------
;; 键盘扫描程序
;; INPUT: P1
;; OUTPUT: KEYCODE
;; INFLUENCED: LASTCODE-上次采样的键码
;;            N_SAME -采样到相同键码的次数
;;            DPTR
;; ---------------------------------------------------
KEY_SCAN:
         MOV     P1, #00FH   ;; 行输出1，列输出0
         NOP
         MOV     A,  P1
         MOV     B,  A       ;; 保存得到的低四位
         MOV     P1, #0F0H   ;; 列输出1，行输出0
         NOP
         MOV     A,  P1      ;; 提取高四位
         ORL     A,  B       ;; 拼装高四位和低四位
         MOV     DPTR, #TAB_KEY
         MOVC    A, @A+DPTR
         ;; A -> 当前所按的按键的编号
         ;; 比较当前按键和上一次所按的按键
         CJNE    A, LASTCODE, NEW_KEY     ;; 如果不等说明有新的按键
         MOV     A, N_SAME
         CJNE    A, THERSHORD, N_SAMENOTEQU
         MOV     KEYCODE, LASTCODE
         INC     N_SAME
         RET
N_SAMENOTEQU:
       JNC     EXIT_KEY            ;; N_SAME大于阈值则直接忽略 退出
       INC     N_SAME              ;; 小于阈值那么N_SAME++
       RET
NEW_KEY:
       MOV     LASTCODE, A         ;; 新键保存在LASTCODE中
       MOV     N_SAME,   #0
       RET
EXIT_KEY:
       RET

TAB_KEY:
        DB      0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH ;0-10H
        DB      0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH ;10-1FH
        DB      0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH ;20-2FH
        DB      0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH ;30-3FH
        DB      0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH ;40-4FH
        DB      0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH ;50-5FH
        DB      0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH ;60-6FH
        DB      0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,01H,0FFH,0FFH,0FFH,05H,0FFH,0AH,0BH,0FFH ;70-7FH
        DB      0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH  ;80-8FH
        DB      0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH  ;90-9FH
        DB      0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH  ;A0-AFH
        DB      0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,02H,0FFH,0FFH,0FFH,06H,0FFH,09H,0CH,0FFH  ;B0-BFH
        DB      0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH  ;C0-CFH
        DB      0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,03H,0FFH,0FFH,0FFH,07H,0FFH,00H,0DH,0FFH  ;D0-DFH
        DB      0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,04H,0FFH,0FFH,0FFH,08H,0FFH,0EH,0FH,0FFH  ;E0-EFH
        DB      0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH,0FFH  ;F0-FFH



;; --------------------------------------------
;; 以下程序段根据不同的KEYCODE, 执行不同的操作
;; --------------------------------------------


;; ---------------------------------------------
;; 是数字时调用这段子程序处理数字
;; INPUT: N_LENGTH, 可能需要调换LED_BUF
;; OUTPUT: NONE
;; INFLUENCED: N_LENGTH, LED_BUF, NUM2_BEGIN
;; ---------------------------------------------

DO_KEY_NUMBER:
        MOV     A,KEYCODE
        CJNE    A,#0FFH,JUDGE_NUM       ;; FFH表示无键按下
        MOV     A, N_LENGTH
        JZ      ZERO_N_LENGTH1          ;; 为了保证退格键只按到恰好消失时LED_BUF也能被清0
        RET
ZERO_N_LENGTH1:
        MOV     R0, LED_BUF
        MOV     @R0, #0
        MOV     N_POINT, #9               ;; 消掉小数点
        RET

;; ------------------------------------------
;; 判断是否是数字按键
;; ------------------------------------------
JUDGE_NUM:
        CJNE    A, #10, ISNUMBER
ISNUMBER:                             ;; 是数字数据 先逐个放到30H开头的内存单元中
        JNC     KEY_RET1              ;; 无借位的话, 直接退出, 不要修改KEYCODE
        JB      OP_B, TO_NUM2         ;; 已经有运算符存在, 输入数据相当于NUM_2
        SJMP    DO_KEY_NUM
TO_NUM2:
        JNB     NUM2_BEGIN, CLR_OPERATOR        ;; 如果NUM2_BEGIN == 0, 还未输入第二个数 要先清LED_BUF
        SJMP    DO_KEY_NUM
CLR_OPERATOR:
        MOV     CLEAR_MEM_HEAD, LED_BUF
        MOV     CLEAR_MEM_N, #16
        LCALL   CLEAR_MEM
        MOV     N_LENGTH, #0
        SETB    NUM2_BEGIN
;; ----------------------------------------------
;; 对按键进行响应
;; ----------------------------------------------
DO_KEY_NUM:
        MOV     R7, N_LENGTH
        MOV     N_POINT, #9               ;; 消掉小数点       ；；；；；；；；；；
        CJNE    R7, #8, TRANSDATALOOP_INIT      ;; 如果输入数据超过8个则阻止输入
        SJMP    KEY_CLR_KEY_AND_RET
;; 以下程序段判断是否需要将LED_BUF中的数据往高位移动一格
TRANSDATALOOP_INIT:
        PUSH    A         ;; 保护A 即按键标号
        MOV     R6, #7
        MOV     A, N_LENGTH
        PUSH    A
        INC     A
        MOV     N_LENGTH, A
        MOV     A, LED_BUF
        ADD     A, #6
        MOV     R0, A
        MOV     R1, A
        INC     R0
        POP     A
        JZ      PUTDATA
;; 将数据从低位往高位移动一格
TRANSDATALOOP:      ;; 将30H开头的内存单元的数据前移
        MOV     A, @R1
        MOV     @R0, A
        DEC     R0
        DEC     R1
        DJNZ    R6, TRANSDATALOOP
;; 按键数据放置到缓冲区最低位
PUTDATA:
        MOV     R0, LED_BUF
        POP     A
        MOV     @R0, A             ;; 放到显示缓冲区第0位
KEY_CLR_KEY_AND_RET:
        MOV     KEYCODE,#0FFH
KEY_RET1:
        RET



;; ---------------------------------------------------------------------------------
;; 是退格键时调用这段子程序处理
;; INPUT: N_LENGTH, KEYCODE, OP_B
;; OUTPUT: NONE
;; INFLUENCED: LED_BUF中的数据少一位, 退格后的高位清0, N_LENGTH
;; ---------------------------------------------------------------------------------
DO_KEY_BACKSPACE:
        MOV     A,KEYCODE
        CJNE    A,#0FFH,JUDGE_BACKSPACE       ;; FFH表示无键按下
        RET
JUDGE_BACKSPACE:
        CJNE    A, #0EH, KEY_RET2    ;; KEYCODE != 0E 说明不是退格键 直接退出
        JB      OP_B, BA_J
        SJMP    BACKSPACE
BA_J:
        JNB     NUM2_BEGIN, BACK_RET  ;; 有运算符存在时, 按下退格键无效, 退出
BACKSPACE:
        MOV A, N_LENGTH
        JZ  ZERO_N_LENGTH
        DEC A
        MOV N_LENGTH, A       ;; N_LENGTH--
        MOV R6, A
        MOV R0, LED_BUF
        MOV R1, LED_BUF
        INC R0
        JZ  ZERO_N_LENGTH
;; 把LED_BUF中的数据左移
BACKSPACELOOP:
        MOV A, @R0
        MOV @R1, A
        MOV @R0, #0
        INC R0
        INC R1
        DJNZ R6, BACKSPACELOOP
BACK_RET:
        MOV  KEYCODE, #0FFH
        RET
;; N_LENGTH == 0时的处理
ZERO_N_LENGTH:
        MOV     R0, LED_BUF
        MOV     @R0, #0
        SJMP    BACK_RET
KEY_RET2:
        RET

;; -------------------------------------------------
;; 是运算符键时调用这段子程序处理
;; INPUT: KEYCODE
;; OUTPUT: LED_BUF中加入运算符显示， OPERATOR改为对应算符
;; INFLUENCED: OP_B
;; -------------------------------------------------
DO_KEY_OP:
        MOV     A,KEYCODE
        CJNE    A,#0FFH,JUDGE_OP       ;; FFH表示无键按下
        RET
JUDGE_OP:
        CLR     C                      ;; 清除CJNE的影响
        SUBB    A, #10                 ;; + - * / -> A B C D
        JC      KEY_RET3               ;; KEYCODE < 10
        CJNE    A, #3, NOT_OP

DO_OP:
        JB      OP_B, END_DO_KEY_OP     ;; 已经有运算符，直接退出
        MOV     OPERATOR, A
        LCALL   SAVE_DATA              ;;将缓冲区中的数据保存到4个Bytes中
        ADD     A, #20
        MOV     R0, LED_BUF
        MOV     @R0, A
        MOV     N_LENGTH, #1
END_DO_KEY_OP:
        MOV     KEYCODE, #0FFH
        SETB    OP_B
        RET
NOT_OP:
        JC      DO_OP
KEY_RET3:
        RET


;; -------------------------------------------------
;; 是=键的时候调用这段程序处理
;; INPUT: KEYCODE
;; OUTPUT: B_EQU, 等号按下标志
;; INFLUENCED: OP_B, NUM2_BEGIN
;; -------------------------------------------------
DO_KEY_EQU:
        MOV     A,KEYCODE
        CJNE    A,#0FFH,JUDGE_EQU       ;; FFH表示无键按下
        RET
JUDGE_EQU:
        CJNE    A, #0FH, KEY_RET4    ;; KEYCODE != 0F 说明不是=键 直接退出
DO_EQU:
        JNB     NUM2_BEGIN, CLR_KEYCODE_RET     ;; NUM2还没开始输入, 按等号键无效
        LCALL   SAVE_DATA
        CLR     NUM2_BEGIN
        CLR     OP_B
        SETB    B_EQU
CLR_KEYCODE_RET:
        MOV     KEYCODE, #0FFH
KEY_RET4:
        RET



;; ---------------------------------------------------
;; 加法求解程序
;; INPUT: NUM1_HEAD, NUM2_HEAD
;; OUTPUT: NUM1_HEAD, LED_BUF
;; INFLUENCE: N_LENGTH, OPERATOR
;; ---------------------------------------------------
CAL_ADD_SUBB:
      MOV  A, OPERATOR
      CJNE A, #2, JUDGE_A_S            ;; 不是+号或者-号直接退出
JUDGE_A_S:
      JNC  EXIT_CAL_ADD                ;; OP >= 2 不是加号或者减号
      JNB  B_EQU, EXIT_CAL_ADD         ;; =号未按下直接退出
DO_ADD:
      LCALL BIN_ADD_SUBB               ;; 加法程序
      CLR  B_EQU
      MOV  OPERATOR, #0FFH
      MOV    BIN_AREA, #NUM1_HEAD
      MOV    BCD_AREA, #BCD1_HEAD

      LCALL  BIN_TO_BCD
      MOV    P_BCDDISP, #BCD1_HEAD
      LCALL  BCD_DISPLAY
      MOV    A, N_LENGTH
      JZ     SHOW_ZERO1
      SJMP   EXIT_CAL_ADD
SHOW_ZERO1:
      INC  N_LENGTH
EXIT_CAL_ADD:
      RET


;; ---------------------------------------------
;; 乘法求解程序
;; INPUT: NUM1_HEAD, NUM2_HEAD
;; OUTPUT: NUM1_HEAD, LED_BUF
;; INFLUENCE: N_LENGTH, OPERATOR
;; ----------------------------------------------
CAL_MUL:
      MOV  A, OPERATOR
      CJNE A, #2, EXIT_CAL_MUL
      JNB  B_EQU, EXIT_CAL_MUL
DO_MUL:
      LCALL BIN_MUL
      MOV   MOV_HEAD_1, #MUL_L                       ;; 积的低4字节转到NUM1_HEAD
      MOV   MOV_HEAD_2, #NUM1_HEAD
      MOV   MOV_N, #4
      LCALL MOV_4BIT

      CLR   B_EQU
      MOV   OPERATOR, #0FFH

      MOV    BIN_AREA, #NUM1_HEAD
      MOV    BCD_AREA, #BCD1_HEAD
      LCALL  BIN_TO_BCD

      MOV    P_BCDDISP, #BCD1_HEAD
      LCALL  BCD_DISPLAY
      MOV    A, N_LENGTH
      JZ     SHOW_ZERO2
      SJMP   EXIT_CAL_MUL
SHOW_ZERO2:
      INC  N_LENGTH
EXIT_CAL_MUL:
      RET


;; -----------------------------------------------------
;; 除法求解程序
;; INPUT: NUM1_HEAD, NUM2_HEAD
;; OUTPUT: NUM1_HEAD -> 整数部分, NUM2_HEAD -> 小数部分
;; INFLUENCED: OPERATOR, N_LENGTH强制显示八位
;; -----------------------------------------------------
CAL_DIV:
      MOV  A, OPERATOR
      CJNE A, #3, EXIT_CAL_DIV
      JNB  B_EQU, EXIT_CAL_DIV
DO_DIV:
    MOV   CLEAR_MEM_HEAD, #DIVIDEND_HEAD
    MOV   CLEAR_MEM_N, #8
    LCALL CLEAR_MEM

    MOV   MOV_HEAD_1, #NUM1_HEAD                     ;; NUM1 -> 被除数
    MOV   MOV_HEAD_2, #DIVIDEND_HEAD
    MOV   MOV_N, #4
    LCALL MOV_4BIT


    LCALL  BIN_DIV                                  ;; 得商整数部分和余数部分

    JB     ZERO_ERROR_BIT, ZERO_ERROR_PROCESS
    SJMP   CAL_DIV_NEXT

ZERO_ERROR_PROCESS:
    LCALL ZERO_PROCESS
    RET

CAL_DIV_NEXT:
    MOV   MOV_HEAD_2, #NUM1_HEAD
    MOV   MOV_HEAD_1, #DIVIDEND_HEAD
    MOV   MOV_N, #4
    LCALL MOV_4BIT                                  ;; 保存整数部分到NUM1中

 ;;  先显示整数部分
    MOV    BIN_AREA, #NUM1_HEAD
    MOV    BCD_AREA, #BCD1_HEAD
    LCALL  BIN_TO_BCD

    MOV    P_BCDDISP, #BCD1_HEAD
    LCALL  BCD_DISPLAY

    ;;  led_buf 中右移整数部分到顶
    LCALL  ADJUST_N_LENGTH

    MOV    A, N_LENGTH
    JZ     RBCD_NEXT            ;; 如果整数部分是全0的话则不需要R0减一
    DEC    R0

RBCD_NEXT:
    MOV    A, LED_BUF   ;; 找37H
    ADD    A, #7
    MOV    R1, A
RBCD_LP:
    MOV    A, @R0
    MOV    @R1, A
    DEC    R0
    DEC    R1
    CJNE   R0, #2FH, RBCD_LP                         ;; 翻页的时候29H要改  -》 LED_BUF - 1

    MOV    A, R1
    INC    A
    CLR    C
    SUBB   A, LED_BUF
    MOV    N_POINT, A


    MOV    FLOAT_N, N_POINT
    LCALL  REMAINDER_TO_FLOAT                       ;; 处理余数部分



    MOV   N_LENGTH, #8          ;; 结果显示8位
    CLR   B_EQU
    MOV   OPERATOR, #0FFH

EXIT_CAL_DIV:
    RET


ZERO_PROCESS:
    MOV    R0, LED_BUF
    MOV    @R0, #25         ;; 显示ERROR
    INC    R0
    MOV    @R0, #0
    INC    R0
    MOV    @R0, #25
    INC    R0
    MOV    @R0, #25
    INC    R0
    MOV    @R0, #24
    MOV    N_LENGTH, #5
    CLR   B_EQU
    MOV   OPERATOR, #0FFH
    MOV   CLEAR_MEM_HEAD, #NUM1_HEAD
    MOV   CLEAR_MEM_N, #8
    LCALL CLEAR_MEM
    RET


;; ----------------------------------------------------
;; 数码管显示程序
;; INPUT: LED_BUF, N_DISP, N_POINT, N_LENGTH
;; OUTPUT: NONE
;; INFLUENCE: N_DISP
;; ----------------------------------------------------
DISPLAY:
        JNB     B_DISPLAY, NOT_DISPLAY
        MOV     A, N_LENGTH
        JNZ     POINT
NOT_DISPLAY:
        MOV     P2, #0FFH
        SJMP    EXIT_DISP
POINT:
        MOV     A, N_POINT
        JZ      NOT_DISP_POINT
        SJMP    LED_NEXT
NOT_DISP_POINT:
        MOV     N_POINT, #9
LED_NEXT:
        ADD     A, LED_BUF
        PUSH    A          ;; 地址压栈保护(要显示小数点的那一位)
        MOV     R1, A
        MOV     A, @R1     ;; 35H内存单元的数+10再查表
        PUSH    A          ;; 数据压栈保护
        ADD     A, #10
        MOV     @R1, A
LED:
        MOV     A, LED_BUF
        ADD     A, N_DISP
        MOV     R0, A
        MOV     A, @R0
        MOV     DPTR, #TAB_LED
        MOVC    A, @A+DPTR
        MOV     P0, A           ;; 输出要显示的数字
        MOV     A,#0FFH
        CLR     C
        INC     N_DISP
        MOV     R7, N_DISP
LOOP_D1:
        RRC     A
        DJNZ    R7,LOOP_D1
        MOV     P2,A
        ;; N_DISP 大于 N_LENGTH时清零
        MOV     A, N_DISP
        ;CJNE    A, N_LENGTH, POP_POINT_DATA          ;; 这里改成SUBB好一些，用CJNE会导致N_DISP大于N_LENGTH，会在按下按键时发生显示异常
        CLR     C
        SUBB    A, N_LENGTH
        JC      POP_POINT_DATA
        MOV     N_DISP, #0
POP_POINT_DATA:
        POP A                     ;; 还原那一位被修改显示小数点的数据
        POP B
        MOV R1, B
        MOV @R1, A
EXIT_DISP:
        RET


TAB_LED:DB 28H, 7EH, 0A2H, 62H, 74H, 61H, 21H, 7AH, 20H, 60H
       ;; 0    1    2     3    4    5    6    7    8    9
        DB 08h, 5EH, 82H, 42H, 54H, 41H, 01H, 5AH, 00H, 40H
       ;; 0.   1.   2.    3.   4.   5.   6.   7.   8.   9.
        DB 0B5H, 0F7H, 34H, 0B6H, 0A1H,  0B7H
           ;20                     24     25
       ;;   +      -    *     /    E      R

;; ------------------------------------------------------------------------
;; 将显示缓冲区的数据BCD码 保存到BCD1_HEAD, BCD2_HEAD中
;; INPUT: LED_BUF, OP_B(0则存到BCD1中, 1则存到BCD2中)
;; OUTPUT: NUM1_HEAD, NUM2_HEAD
;; ------------------------------------------------------------------------
SAVE_DATA:
       PUSH    A                  ;; 保护A 和 PSW
       PUSH    PSW
       CLR  PSW.3
       ;; ----- 检查缓冲区最前端是否有-号 -------
       LCALL  ADJUST_N_LENGTH     ;; 找最高位
       DEC    R0                  ;; R0指向最高位
       CLR    BUMA_SIGNED         ;; 借用 保存符号位
       CLR    ZERO_ERROR_BIT
       CJNE   R0, #02FH, SAVE_DATA_NEXT        ;; R0 == 2FH, 说明缓冲区里面全是0, 第二个运算数是0, 那么保持其符号位是0不变, 否则会导致溢出错误
       SETB   ZERO_ERROR_BIT      ;; 待保存的数为0则ZERO_ERROR_BIT置1
       SJMP   SAVE_DATA_CONTINUE
SAVE_DATA_NEXT:
       CJNE   @R0, #21, SAVE_DATA_CONTINUE
       SETB   BUMA_SIGNED
       MOV    @R0, #0
       ;;
SAVE_DATA_CONTINUE:
       LCALL  GET_INT           ;; 取整数保存
       MOV  R7, #4
       MOV  R0, LED_BUF
       MOV  R1, LED_BUF
       INC  R1
       SETB PSW.3   ;;切换寄存器工作组
       JNB  OP_B, SAVE_TO_NUM_1             ;; 如果没有操作符就存到NUM1
       MOV  R0, #BCD2_HEAD
       SJMP SAVE_DATA_LOOP_INIT
SAVE_TO_NUM_1:
       MOV  R0, #BCD1_HEAD
       ;; R0取低字节，R1取高字节
SAVE_DATA_LOOP_INIT:
       MOV  BCD_AREA, R0
       MOV  A, BCD_AREA
       CLR  C
       SUBB A, #4
       MOV  BIN_AREA, A
       CLR  PSW.3
SAVE_DATA_LOOP:
       MOV  A, @R1
       SWAP A
       ANL  A, #0F0H
       MOV  B, A
       MOV  A, @R0
       ANL  A, #00FH
       ORL  A, B
       INC  R1
       INC  R1
       INC  R0
       INC  R0
       SETB PSW.3   ;;切换寄存器工作组
       MOV  @R0, A
       INC  R0
       CLR  PSW.3
       DJNZ R7, SAVE_DATA_LOOP

       ;; 如果OP为-号而且待保存的第二个操作数不为0, 那么NUM2符号位取反
       MOV   R5, OPERATOR
       CJNE  R5, #1, SAVE_D_END
       JNB   OP_B, SAVE_D_END
       JB    ZERO_ERROR_BIT, SAVE_D_END       ;; 待保存的操作数为0，不需要取反符号位, 否则会导致溢出
       CPL   BUMA_SIGNED
SAVE_D_END:
       LCALL BCD_TO_BIN
       CLR   ZERO_ERROR_BIT
       POP  PSW
       POP  A
       RET

;; ------------------------------------------
;; 将LED_BUF中的数取整数部分 , 即把小数部分去除掉, 整数部分回移
;; INPUT: N_POINT, LED_BUF
;; OUTPUT:
;; INFLUENCE:
;; -------------------------------------------
GET_INT:
      PUSH  PSW
      PUSH  A

      MOV   A, N_POINT
      CJNE  A, #8, XX8
XX8:
      JC    GET_INT_PART
      SJMP  GET_INT_END
GET_INT_PART:
      SETB  RS0                 ;; 用第2组寄存器         10H~17H
      CLR   RS1

      MOV  A, N_POINT
      ADD  A, LED_BUF
      MOV  R0, A
      MOV  R1, LED_BUF
      MOV  A, #8
      CLR  C
      SUBB A, N_POINT
      MOV  R7, A               ;; 循环次数确定
      ;; 清0小数部分, 整数部分挪到开头

      CLR  RS0                          ;; 换寄存器工作组 保证R0不要被破坏
      MOV  CLEAR_MEM_HEAD, LED_BUF
      MOV  CLEAR_MEM_N, N_POINT
      LCALL CLEAR_MEM
      SETB RS0
GET_INT_LP:
      MOV  A, @R0
      MOV  @R1, A
      MOV  @R0, #0
      INC  R0
      INC  R1
      DJNZ R7, GET_INT_LP
      MOV  N_POINT, #9
GET_INT_END:
      POP  A
      POP  PSW
      RET

;; ------------------------------------------
;; 二进制4字节带符号数加减法
;; 在内存单元中的数均为原码
;; INPUT: NUM1_HEAD, NUM2_HEAD
;; OUTPUT: 和放在NUM1中
;; INFLUENCE:
;; ------------------------------------------
BIN_ADD_SUBB:
    ;; 两个数都取补码
    MOV  BUMA_HEAD, #NUM2_HEAD
    LCALL BUMA
    MOV  BUMA_HEAD, #NUM1_HEAD         ;; BUMA_HEAD  保存   NUM1_HEAD
    LCALL BUMA
    MOV  R7, #4
    CLR  C
    MOV  R0, #NUM1_HEAD
    MOV  R1, #NUM2_HEAD
BIN_ADD_LP:
    MOV   A, @R0
    ADDC  A, @R1
    MOV   @R0, A
    INC   R0
    INC   R1
    DJNZ  R7, BIN_ADD_LP
    LCALL  BUMA                       ;; 结果是补码, 转为原码表示
    RET


;; ------------------------------------------
;; 二进制4字节数求补码
;; 在内存单元中的数均为原码
;; INPUT:
;; OUTPUT:
;; INFLUENCE:
;; -------------------------------------------
BUMA:
    MOV  R7, #4
    MOV  R0, BUMA_HEAD
    ;;------ 保存最高位的符号位 ------------
    MOV  A, R0
    ADD  A, #3
    MOV  R1, A
    MOV  A, @R1
    RLC  A
    MOV  BUMA_SIGNED, C
    JNC  BUMA_END
    ;;-------------------------------------
    SETB C

BUMA_LP:
    MOV  A, @R0
    CPL  A
    ADDC A, #0
    MOV  @R0, A
    INC  R0
    DJNZ R7, BUMA_LP

    ;;-------- 还原最高位符号位 -----------
    DEC  R0
    MOV  C, BUMA_SIGNED
    MOV  A, @R0
    MOV  ACC.7, C
    MOV  @R0, A
    ;;-------------------------------------
BUMA_END:
    RET



;; ----------------------------------------------
;; 二进制4字节带符号数乘法
;; 在内存单元中的数均为原码
;; INPUT: NUM1_HEAD, NUM2_HEAD
;; OUTPUT: MUL_H, MUL_L
;; INFLUENCE:
;; ----------------------------------------------

BIN_MUL:
    ;;  符号位处理, 乘积的符号位等于两个数的符号位异或
    MOV  SIGNED_BIT_HEAD, #NUM1_HEAD
    LCALL  SAVE_SIGNED
    MOV   C, SIGNED_BIT
    MOV   MUL1_BIT, C

    MOV  SIGNED_BIT_HEAD, #NUM2_HEAD
    LCALL  SAVE_SIGNED
    MOV   C, SIGNED_BIT
    MOV   MUL2_BIT, C


    MOV   C, MUL2_BIT
    ANL   C, /MUL1_BIT
    MOV   BUMA_SIGNED, C        ;; A /B
    MOV   C, MUL1_BIT
    ANL   C, /MUL2_BIT
    ORL   C, BUMA_SIGNED
    MOV   MUL1_BIT, C
    ;;  符号结果用MUL1_BIT保存，同时经过ALLRL, ALLRR, 将符号位全部置0, 取绝对值相乘

    ;;  先清空乘积部分
    MOV  CLEAR_MEM_HEAD, #MUL_L
    MOV  CLEAR_MEM_N   , #8             ;; 清空8个字节
    LCALL CLEAR_MEM
    MOV  R6, #32
BIN_MUL_LP:
    MOV   SHIFT_4BIT_P, #NUM2_HEAD       ;; 乘数右移进C中
    MOV   SHIFT_N, #4
    LCALL ALLRR
    JNC   RRMUL
    ;; 乘数这一位是1, 积的高4字节与被乘数相加
    CLR  C
    SETB PSW.3
    MOV  R5, #4
    MOV  R0, #NUM1_HEAD
    MOV  R1, #MUL_H
MUL_ADD_LP:
    MOV  A, @R0
    ADDC A, @R1
    MOV  @R1, A
    INC  R0
    INC  R1
    DJNZ R5, MUL_ADD_LP
    CLR  PSW.3
;; 积高4位低4位整体右移
RRMUL:
    MOV  SHIFT_4BIT_P, #MUL_L
    MOV  SHIFT_N, #8
    LCALL ALLRR
    DJNZ  R6, BIN_MUL_LP


;; 决定符号位
    MOV   A, #MUL_L
    ADD   A, #3
    MOV   R1,  A
    MOV   A, @R1
    MOV   C, MUL1_BIT
    MOV   ACC.7, C
    MOV   @R1, A
    RET



;; ------------------------------------------------
;; 二进制8字节除以4字节带符号数除法
;; 在内存单元中的数均为原码
;; INPUT: NUM1_HEAD, NUM2_HEAD
;; OUTPUT: REMAINDER_HEAD, DIVIDEND_HEAD
;; INFLUENCE:
;; -------------------------------------------------

BIN_DIV:
    ;; 符号位确定
    MOV  A, #DIVIDEND_HEAD
    MOV  SIGNED_BIT_HEAD, A
    LCALL  SAVE_SIGNED
    MOV   C, SIGNED_BIT
    MOV   MUL1_BIT, C

    MOV  SIGNED_BIT_HEAD, #DIVISOR_HEAD
    LCALL  SAVE_SIGNED
    MOV   C, SIGNED_BIT
    MOV   MUL2_BIT, C


    MOV   C, MUL2_BIT
    ANL   C, /MUL1_BIT
    MOV   BUMA_SIGNED, C        ;; A /B
    MOV   C, MUL1_BIT
    ANL   C, /MUL2_BIT
    ORL   C, BUMA_SIGNED
    MOV   MUL1_BIT, C


    ;; 判断除数是否等于0, 等于0直接溢出 ZERO_ERROR_BIT = 1 否则 = 0
    LCALL JUDGE_DIVISOR_Z
    JB    ZERO_ERROR_BIT, BIN_DIV_END

    MOV   SHIFT_4BIT_P, #DIVIDEND_HEAD
    MOV   SHIFT_N, #12                ;; 8+4 = 12 字节左移
    MOV   R4, #32                     ;; 被除数全部移出, 共 4*8 = 64次
    ;; 清空余数部分
    MOV   CLEAR_MEM_HEAD, #REMAINDER_HEAD
    MOV   CLEAR_MEM_N   , #4
    LCALL CLEAR_MEM

BIN_DIV_LP:
    LCALL  ALLRL
    SETB   PSW.3
    LCALL  JUDGE_AND_UPDATE_REMAINDER            ;; 判断余数部分是否>除数 , > 则更新 余数 = 余数-除数, C=0, 否则不更新 C=1
    JC     BIN_DIV_LP_JUDGE
;;  被除数部分最低字节最低位置1
    MOV    R0, #DIVIDEND_HEAD
    MOV    A, @R0
    SETB   ACC.0
    MOV    @R0, A
BIN_DIV_LP_JUDGE:
    CLR    PSW.3
    DJNZ   R4, BIN_DIV_LP

;; 还原符号位
    MOV   A, #DIVIDEND_HEAD
    ADD   A, #3                      ;; 找到商部分最高字节    3是4字节除法
    MOV   R1,  A
    MOV   A, @R1
    MOV   C, MUL1_BIT
    MOV   ACC.7, C
    MOV   @R1, A

BIN_DIV_END:
    RET


;; ---------------------------------------------
;; 在除法中判断余数部分是否大于除数部分的子程序
;; INPUT: REMAINDER_HEAD, DIVISOR_HEAD
;; OUTPUT: NONE
;; INFLUENCE: A, REMAINDER_HEAD
;; ---------------------------------------------
JUDGE_AND_UPDATE_REMAINDER:
    MOV  R0, #REMAINDER_HEAD
    MOV  R1, #DIVISOR_HEAD
    MOV  R3, #4
    CLR  C
JUDGE_REMAINDER_LP:             ;; 先做减法, 判断最后的结果是否有 C = 1, =1说明余数小
    MOV  A, @R0
    SUBB A, @R1
    PUSH A                      ;; 减法得到的结果压栈保存, 如果最后不需要更新则直接丢弃
    INC  R0
    INC  R1
    DJNZ R3, JUDGE_REMAINDER_LP
    JC   DISCARD_RESULT        ;; 余数小则直接丢掉减法的结果

;; 否则则需要更新余数部分
    MOV  R3, #4
UPDATE_RESULT_LP:
    DEC  R0
    POP  A
    MOV  @R0, A
    DJNZ R3, UPDATE_RESULT_LP
    SJMP JUDGE_REMAINDER_END
DISCARD_RESULT:                ;; 将减法得到的四字节数字丢弃
    POP  A
    POP  A
    POP  A
    POP  A
JUDGE_REMAINDER_END:
    RET

;; ----------------------------------------
;; 在除法中判断除数部分是否为0的子程序
;; INPUT: DIVISOR_HEAD
;; OUTPUT: NONE
;; INFLUENCE: ZERO_ERROR_BIT : 如果除数不是0则置1
;; ----------------------------------------
JUDGE_DIVISOR_Z:
    SETB ZERO_ERROR_BIT
    MOV  R0, #DIVISOR_HEAD
    MOV  R2, #4
JUDGE_DIVISOR_Z_LP:
    MOV  A,  @R0
    JNZ  DIVISOR_NOT_ZERO                     ;; 有一个字节不是0即可
    INC  R0
    DJNZ R2, JUDGE_DIVISOR_Z_LP
    SJMP JUDGE_DIVISOR_Z_END
DIVISOR_NOT_ZERO:
    CLR  ZERO_ERROR_BIT
JUDGE_DIVISOR_Z_END:
    RET

;; ------------------------------------------
;; 余数部分转化成小数部分的子程序
;; INPUT: DIVISOR_HEAD, MUL_L -> 借用积的低四字节寄存器，FLOAT_N -> 小数位数的个数
;; OUTPUT: DIVIDEND_HEAD, REMAINDER_HEAD
;; INFLUENCE: NONE
;; ------------------------------------------
REMAINDER_TO_FLOAT:
    ;; 余数左移3位 + 余数左移1位 = 10*余数
    MOV  CLEAR_MEM_HEAD, #DIVIDEND_HEAD
    MOV  CLEAR_MEM_N, #4
    LCALL CLEAR_MEM                              ;; 这里只做正整数的除法
    SETB RS0
    SETB RS1
    MOV  A,  LED_BUF
    ADD  A,  FLOAT_N
    MOV  R0, A
    DEC  R0
    CLR  RS0
    CLR  RS1
    MOV  R3, FLOAT_N
    INC  R3
MUL10LP:
;; 余数乘以10
    MOV  SHIFT_4BIT_P, #REMAINDER_HEAD
    MOV  SHIFT_N, #4
    MOV  MOV_HEAD_1, #REMAINDER_HEAD
    MOV  MOV_HEAD_2, #MUL_L
    MOV  MOV_N, #4
    LCALL ALLRL
    LCALL MOV_4BIT
    LCALL ALLRL
    LCALL ALLRL
    CLR   C
    MOV   R0, #REMAINDER_HEAD
    MOV   R1, #MUL_L
    MOV   R2, #4
RTF_ADD_LP:
    MOV   A, @R0
    ADDC  A, @R1
    MOV   @R0, A
    INC   R0
    INC   R1
    DJNZ  R2, RTF_ADD_LP            ;; 乘10以后再存回 余数部分中
;; 余数移动到被除数中
    MOV   MOV_HEAD_1, #REMAINDER_HEAD
    MOV   MOV_HEAD_2, #DIVIDEND_HEAD
    MOV   MOV_N, #4
    LCALL MOV_4BIT
;; 余数*10/ 除数, 做FLOAT_N次
    LCALL BIN_DIV
    SETB RS0
    SETB RS1
    CJNE R0, #2FH, LAST_ROUND
    SJMP LR_NEXT
LAST_ROUND:
    MOV  @R0, DIVIDEND_HEAD             ;; 余数*10/ 除数的结果必然小于10, 因此不用经过二进制->BCD的转换，可以直接放到DIVIDEND_HEAD中
    DEC  R0
LR_NEXT:
    CLR  RS0
    CLR  RS1
    DJNZ R3, MUL10LP
    LCALL ROUND
    RET


;; ------------------------------------------
;; 小数部分四舍五入的子程序
;; INPUT: DIVISOR_HEAD, MUL_L -> 借用积的低四字节寄存器，FLOAT_N -> 小数位数的个数
;; OUTPUT: DIVIDEND_HEAD, REMAINDER_HEAD
;; INFLUENCE: NONE
;; -------------------------------------------
ROUND:
    MOV  A, DIVIDEND_HEAD
    CJNE A, #5, BIG_ROUND
BIG_ROUND:
    CPL  C
    JNC  ROUND_END
    MOV  R0, LED_BUF
    MOV  R3, #8
ROUND_LP:
    MOV  A, @R0
    ADDC A, #0
    MOV  @R0, A
    INC  R0
    DJNZ R3, ROUND_LP
ROUND_END:
    RET

;;  -----------------------------------------
;;  以下是BCD码与二进制的相互转换程序
;;  支持将带符号数与BCD码的互相转换, 二进制转BCD时符号位存在 SIGNED_BIT中
;;  BCD转二进制要利用SAVE_DATA程序段中给出的BUMA_BIT来确定符号位
;;  ------------------------------------------

;; ---------------------------------------------
;; 4字节二进制转BCD码子程序   加三移位法
;; INPUT: BIN_AREA，BCD_AREA
;; OUTPUT: SIGNED_BIT，BCD_AREA
;; INFLUENCE: BIN_AREA
;; ----------------------------------------------
BIN_TO_BCD:
    ;; 先取二进制码最高位, 保存符号位
    MOV  SIGNED_BIT_HEAD, BIN_AREA
    LCALL  SAVE_SIGNED
    ;; 先清0 BCD区
    MOV  CLEAR_MEM_HEAD, BCD_AREA
    MOV  CLEAR_MEM_N,    #4
    LCALL  CLEAR_MEM
    MOV  R5, #32        ;; 一共32次移位
    MOV  SHIFT_N, #8
    MOV  SHIFT_4BIT_P, BIN_AREA
BIN_TO_BCD_LP:
    ;; BCD正向调整
    MOV   R6, #4
    MOV   R0, BCD_AREA
BCD_ADJUST_LP:
    LCALL BCD_ADJUST
    INC   R0
    DJNZ  R6, BCD_ADJUST_LP

    ;; BCD，BIN码区整体左移
    LCALL ALLRL
    DJNZ  R5, BIN_TO_BCD_LP
    RET


;; --------------------------------------------
;; BCD码正向调整: 如果当前BCD单元的内容大于4, 则要对其做加三处理
;; INPUT: @R0, 当前字节的内容
;; OUTPUT: 原址运算, 调整后的BCD码
;; INFLUENCE:
;; --------------------------------------------
BCD_ADJUST:
     MOV  A, @R0
     ADD  A, #03H       ;; 低字节+3看是否大于等于8
     JB   ACC.3, BCD_ADJUST_L
     SJMP BCD_ADJUST_JUDGE_H
BCD_ADJUST_L:   ;; 需要做加3调整
     MOV  @R0, A    ;; 保存

BCD_ADJUST_JUDGE_H:
     MOV  A, @R0
     ADD  A, #30H       ;; 高字节+3看是否大于等于8
     JB   ACC.7, BCD_ADJUST_H
     SJMP BCD_ADJUST_END
BCD_ADJUST_H:
     MOV  @R0, A
BCD_ADJUST_END:
     RET



;; ----------------------------------------------
;; N个字节左移程序(N <= 255)
;; INPUT: 需要左移最低位字节的内存单元地址 SHIFT_4BIT_P, Bytes数量SHIFT_N
;; OUTPUT: 原址运算, 运算结果相当于原来的四个BYTE中的单元的内容左移, 最低位补0 , C保存最高字节的最高位
;; INFLUENCE: A, C, PSW, R0
;; ----------------------------------------------

ALLRL:
    CLR  C
    MOV  R0, SHIFT_4BIT_P
    MOV  R7, SHIFT_N
ALLRL_LP:
    MOV  A,  @R0                ;; A中存最低位
    RLC  A
    MOV  @R0,  A                ;; 回存
    INC  R0
    DJNZ R7, ALLRL_LP
    RET

;; -----------------------------------------
;; BCD码转二进制BIN子程序   减三移位法   实际上是BCD_TO_BIN的逆过程
;; INPUT: BIN_AREA, BCD_AREA
;; OUTPUT: BIN_AREA
;; INFLUENCE: BCD_AREA
;; 必须先调用SAVE_DATA再调用BCD_TO_BIN，此时可以根据SAVE_DATA中确定的BUMA_BIT
;; -----------------------------------------
BCD_TO_BIN:
    ;; 先清0 BIN区
    MOV  CLEAR_MEM_HEAD, BIN_AREA
    MOV  CLEAR_MEM_N,    #4
    LCALL CLEAR_MEM
    MOV  R5, #32
    MOV  SHIFT_4BIT_P, BIN_AREA
    MOV  SHIFT_N, #8
BCD_TO_BIN_LP:
    ;; BCD+BIN区整体右移
    LCALL ALLRR

    ;; BCD反向调整
    MOV  R0, BCD_AREA
    MOV  R6, #4
BCD_IADJUST_LP:
    LCALL BCD_IADJUST
    INC   R0
    DJNZ  R6, BCD_IADJUST_LP
    DJNZ  R5, BCD_TO_BIN_LP
    ;; -------------- 对最高位的符号进行调整 ---------------------
    ;; 如果 SAVE_DATA 中使得 BUMA_BIT == 1, 那么要修改最高位的符号
    MOV   A, BIN_AREA
    ADD   A, #3      ;; 找最高字节
    MOV   R1, A
    MOV   A, @R1
    MOV   C, BUMA_SIGNED
    MOV   ACC.7, C
    MOV   @R1, A
    RET

;; ----------------------------------------------------
;; BCD码反向调整  如果当前的BCD单元的内容大于8, 则需要做减3处理
;; INPUT: @R0
;; OUTPUT: 原址运算, 调整后的BCD码
;; INFLUENCE:
;; -----------------------------------------------------
BCD_IADJUST:
     MOV  A, @R0
     ;; 判断低字节BCD码是否>=8, 是则需要-03H
     JB   ACC.3, BCD_IADJUST_L
     SJMP  BCD_IADJUST_JUDGE_H
BCD_IADJUST_L:
     CLR   C
     SUBB  A, #03H
BCD_IADJUST_JUDGE_H:
     JB   ACC.7, BCD_IADJUST_H
     SJMP  BCD_IADJUST_END
BCD_IADJUST_H:
     CLR   C
     SUBB  A, #30H
BCD_IADJUST_END:
     MOV  @R0, A
     RET


;; -------------------------------------------
;; 4个字节右移程序
;; INPUT: 需要右移最低位字节的内存单元地址 SHIFT_4BIT_P, Bytes数量SHIFT_N
;; OUTPUT: 原址运算, 运算结果相当于原来的四个BYTE中的单元的内容右移, 最高位补0, C保存最低字节的最低位
;; INFLUENCE: A, C, PSW, R0
;; --------------------------------------------
ALLRR:
    CLR  C
    MOV  R0, SHIFT_4BIT_P
    MOV  A, R0
    ADD  A, SHIFT_N
    DEC  A
    MOV  R0, A          ;; R0里的数加SHIFT_N，找到最高地址的字节 30H -> 33H
    MOV  R7, SHIFT_N
ALLRR_LP:
    MOV  A,  @R0                ;; A中存最低位
    RRC  A
    MOV  @R0,  A                ;; 回存
    DEC  R0
    DJNZ R7, ALLRR_LP
    RET


;; --------------------------------------------------
;; INPUT: CLEAR_MEM_HEAD, CLEAR_MEM_N
;; OUTPUT: NONE
;; INFLUENCE: CLEAR_MEM_HEAD
;; --------------------------------------------------
CLEAR_MEM:
    MOV  R0, CLEAR_MEM_HEAD
    MOV  R7, CLEAR_MEM_N
CLEAR_MEM_LP:
    MOV  @R0, #0
    INC  R0
    DJNZ R7,  CLEAR_MEM_LP
    RET


;; -------------------------------------------------------
;; 取出4字节二进制数的符号位, 并取该数的绝对值
;; INPUT: 最低字节地址SAVE_BIT_HEAD
;; OUTPUT: 符号位保存在SAVE_BIT中
;; INFLUENCE: R1, PSW, A, SAVE_BIT
;; --------------------------------------------------------

SAVE_SIGNED:
    MOV  A, SIGNED_BIT_HEAD
    ADD  A, #3
    MOV  R1,  A
    MOV  A, @R1
    RLC  A  ;; 符号位移到C中
    RR   A
    MOV  @R1, A
    MOV  SIGNED_BIT, C
    RET


;; --------------------------------------------
;; N字节数据传送子程序
;; INPUT: MOV_HEAD_1, MOV_HEAD_2, MOV_N
;; OUTPUT: 从1搬运数据到2
;; INFLUENCE:  A, R0
;; --------------------------------------------

MOV_4BIT:
    MOV  R0, MOV_HEAD_1
    MOV  R1, MOV_HEAD_2
    MOV  R2, MOV_N
MOV_4BIT_LP:
    MOV  A, @R0
    MOV  @R1, A
    INC  R0
    INC  R1
    DJNZ R2, MOV_4BIT_LP
    RET


;; -----------------------------------------------
;; 将4Bytes的压缩型BCD码拆成8位非压缩型BCD码, 用于将运算结果显示到数码管上
;; INPUT: 待转换数据最低位的地址  P_BCDDISP,
;; OUTPUT: LED_BUF
;; INFLUENCE:
;; 先调用 BIN_TO_BCD再调用这段程序
;; -----------------------------------------------
BCD_DISPLAY:
       PUSH  A
       PUSH  PSW
       MOV   R0, LED_BUF
       MOV   R1, P_BCDDISP
       MOV   R7, #4
BCD_DISPLAY_LOOP:
       MOV   A, @R1
       ANL   A, #0FH    ;; 提取低四位

       MOV   @R0, A
       INC   R0

       MOV   A, @R1
       ANL   A, #0F0H
       SWAP  A
       MOV   @R0, A
       INC   R0
       INC   R1

       DJNZ  R7, BCD_DISPLAY_LOOP
       LCALL  ADJUST_N_LENGTH                 ;; 调整显示位数
       JB    SIGNED_BIT, BCD_N_PROCESS            ;; 处理负数
       SJMP  BCD_DISPLAY_END
BCD_N_PROCESS:
       MOV   @R0, #21
       INC   N_LENGTH
BCD_DISPLAY_END:
       POP   PSW
       POP   A
       RET


;; ----------------------------------------
;;  检查当前LED_BUF里面有多少有效数（非0）
;;  INPUT: NONE
;;  INFLUENCED:  R0, N_LENGTH
;;  最后R0中保存的是下一位数   1 2 3 0 0 0 0 0 -> N_LENGTH == 3, R0 = LED_BUF + N_LENGTH  = 33
;; ----------------------------------------
ADJUST_N_LENGTH:
       PUSH A
       PUSH PSW
       MOV  A, LED_BUF
       ADD  A, #7
       MOV  R0, A
       MOV  R7, #8
ADJUST_LOOP:
       MOV  A, @R0
       JNZ  END_ADJUST_LOOP
       DEC  R0
       DJNZ R7, ADJUST_LOOP
END_ADJUST_LOOP:
       INC  R0
       MOV  A, R0
       CLR  C
       SUBB A, LED_BUF
       MOV  N_LENGTH, A

       POP  PSW
       POP  A
       RET
