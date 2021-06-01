package sdl_net

import _c "core:c"
import sdl "shared:sdl"

/* Macros */

MAJOR_VERSION :: 2;
MINOR_VERSION :: 0;
PATCHLEVEL :: 1;
INADDR_ANY :: 0x0;
INADDR_NONE :: 0xFFFFFFFF;
INADDR_LOOPBACK :: 0x7F000001;
INADDR_BROADCAST :: 0xFFFFFFFF;
MAX_UDPCHANNELS :: 32;
MAX_UDPADDRESSES :: 4;
DATA_ALIGNED :: 0;

version :: sdl.version;

IPaddress :: struct {
    host : sdl.Uint32,
    port : sdl.Uint16,
};

_TCPsocket :: struct {};

_UDPsocket :: struct {};

UDPpacket :: struct {
    channel : _c.int,
    data    : ^sdl.Uint8,
    len     : _c.int,
    maxlen  : _c.int,
    status  : _c.int,
    address : IPaddress,
};

TCPsocket :: ^_TCPsocket;

UDPsocket :: ^_UDPsocket;

_SocketSet :: struct {};

_GenericSocket :: struct {
    ready : _c.int,
};

SocketSet :: ^_SocketSet;

GenericSocket :: ^struct {
    ready : _c.int,
};


/***** libSDL2_net *****/
foreign import libSDL2_net "system:libSDL2_net.so"

/* Procedures */
@(link_prefix="SDLNet_")
foreign libSDL2_net {
    Linked_Version            :: proc() -> ^version ---;
    Init                      :: proc() -> _c.int ---;
    Quit                      :: proc() ---;
    ResolveHost               :: proc(address : ^IPaddress, host : cstring, port : sdl.Uint16) -> _c.int ---;
    ResolveIP                 :: proc(ip : ^IPaddress) -> cstring ---;
    GetLocalAddresses         :: proc(addresses : ^IPaddress, maxcount : _c.int) -> _c.int ---;
    TCP_Open                  :: proc(ip : ^IPaddress) -> TCPsocket ---;
    TCP_Accept                :: proc(server : TCPsocket) -> TCPsocket ---;
    TCP_GetPeerAddress        :: proc(sock : TCPsocket) -> ^IPaddress ---;
    TCP_Send                  :: proc(sock : TCPsocket, data : rawptr, len : _c.int) -> _c.int ---;
    TCP_Recv                  :: proc(sock : TCPsocket, data : rawptr, maxlen : _c.int) -> _c.int ---;
    TCP_Close                 :: proc(sock : TCPsocket) ---;
    ResizePacket              :: proc(packet : ^UDPpacket, newsize : _c.int) -> _c.int ---;
    FreePacket                :: proc(packet : ^UDPpacket) ---;
    FreePacketV               :: proc(packetV : ^^UDPpacket) ---;
    UDP_Open                  :: proc(port : sdl.Uint16) -> UDPsocket ---;
    UDP_SetPacketLoss         :: proc(sock : UDPsocket, percent : _c.int) ---;
    UDP_Bind                  :: proc(sock : UDPsocket, channel : _c.int, address : ^IPaddress) -> _c.int ---;
    AllocPacket               :: proc(size : _c.int) -> ^UDPpacket ---;
    AllocPacketV              :: proc(howmany : _c.int, size : _c.int) -> ^^UDPpacket ---;
    UDP_Unbind                :: proc(sock : UDPsocket, channel : _c.int) ---;
    UDP_GetPeerAddress        :: proc(sock : UDPsocket, channel : _c.int) -> ^IPaddress ---;
    UDP_SendV                 :: proc(sock : UDPsocket, packets : ^^UDPpacket, npackets : _c.int) -> _c.int ---;
    UDP_Send                  :: proc(sock : UDPsocket, channel : _c.int, packet : ^UDPpacket) -> _c.int ---;
    UDP_RecvV                 :: proc(sock : UDPsocket, packets : ^^UDPpacket) -> _c.int ---;
    UDP_Recv                  :: proc(sock : UDPsocket, packet : ^UDPpacket) -> _c.int ---;
    UDP_Close                 :: proc(sock : UDPsocket) ---;
    AllocSocketSet            :: proc(maxsockets : _c.int) -> SocketSet ---;
    AddSocket                 :: proc(set : SocketSet, sock : GenericSocket) -> _c.int ---;
    DelSocket                 :: proc(set : SocketSet, sock : GenericSocket) -> _c.int ---;
    CheckSockets              :: proc(set : SocketSet, timeout : sdl.Uint32) -> _c.int ---;
    FreeSocketSet             :: proc(set : SocketSet) ---;
    SetError                  :: proc(fmt : cstring, #c_vararg __args : ..any) ---;
    GetError                  :: proc() -> cstring ---;
}

