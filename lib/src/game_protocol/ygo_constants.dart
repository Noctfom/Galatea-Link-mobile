// YGOPro 网络消息常量，区分客户端发送和服务器返回类型

const int ctosResponse = 0x01;
const int ctosUpdateDeck = 0x02;
const int ctosHandResult = 0x03;
const int ctosTpResult = 0x04;
const int ctosPlayerInfo = 0x10;
const int ctosCreateGame = 0x11;
const int ctosJoinGame = 0x12;
const int ctosLeaveGame = 0x13;
const int ctosSurrender = 0x14;
const int ctosTimeConfirm = 0x15;
const int ctosHsReady = 0x22;
const int ctosHsStart = 0x25;
const int ctosChat = 0x16;

const int stocGameMsg = 0x01;
const int stocErrorMsg = 0x02;
const int stocSelectHand = 0x03;
const int stocSelectTp = 0x04;
const int stocHandResult = 0x05;
const int stocJoinGame = 0x12;
const int stocTypeChange = 0x13;
const int stocHsPlayerExit = 0x14;
const int stocDuelStart = 0x15;
const int stocDuelEnd = 0x16;
const int stocTimeLimit = 0x18;
const int stocChat = 0x19;
const int stocHsPlayerEnter = 0x20;
const int stocHsPlayerChange = 0x21;
const int stocHsWatchChange = 0x22;

const int playerChangeObserve = 0x08;
const int playerChangeReady = 0x09;
const int playerChangeNotReady = 0x0A;
const int playerChangeLeave = 0x0B;
