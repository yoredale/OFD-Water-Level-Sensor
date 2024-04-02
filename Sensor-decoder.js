/*
  ____ __            __  ____    ____
 / ___\\ \    /\    / / / ___\  /  __\
| (___  \ \  /  \  / / | /     | /
 \___ \  \ \/ /\ \/ /  | |     | |
 ___)  |  \  /  \  /   | \____ | \____ 
|_____/    \/    \/     \____/  \____/
 

  JS Decoder for the sensor, works in Chirpstack 4.


  Based on the ELSYS simple payload decoder. 
  Use it as it is or remove the bugs :)
  www.elsys.se
  peter@elsys.se
*/

var TYPE_BAT        = 0x34; //Battery 1 byte  0-100%
var TYPE_CLOOP      = 0x3d; //Current loop 0-1023


function bin16dec(bin) {
    var num=bin&0xFFFF;
    if (0x8000 & num)
        num = - (0x010000 - num);
    return num;
}
function bin8dec(bin) {
    var num=bin&0xFF;
    if (0x80 & num) 
        num = - (0x0100 - num);
    return num;
}
function hexToBytes(hex) {
    for (var bytes = [], c = 0; c < hex.length; c += 2)
        bytes.push(parseInt(hex.substr(c, 2), 16));
    return bytes;
}
function DecodeElsysPayload(data){
    var obj = new Object();
    for(i=2;i<data.length;i++){
	//console.log(data.length);
        //console.log(data[i]);
        switch(data[i]){
        case TYPE_BAT: // Battery Level
            var bat=(data[i+1]);
            obj.battery_level=bat;
            i+=1;
            break;
        case TYPE_CLOOP: //Current Loop
            obj.current_loop=(data[i+2]<<8)|(data[i+1]);
	    depth = obj.current_loop - 200;
	    if (depth <= 0) {
		depth = 0;
	      } else {
		  if (depth >= 823) {
		      depth = 3;
		  } else {
		      depth = 3 * depth / 823;
		  }
	    }
	    obj.depth=(depth.toPrecision(2));
            i+=2;
            break;
        default: //somthing is wrong with data
            i=data.length;
            break;
        }
    }
    return obj;
}

function decodeUplink(input) {
    return {
        "data": DecodeElsysPayload(input.bytes)
    }
}
