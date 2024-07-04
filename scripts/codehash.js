const { exec } = require('child_process');

const defaultAddress = process.env.DEFAULTADDRESS
const rpc = process.env.RPCURL

exec('echo $(cast keccak $(cast code '+defaultAddress+' --rpc-url '+rpc+') > codehash.txt)');
exec('echo "Address: '+defaultAddress+'"');
exec('echo "RPC: '+rpc+'"');
exec('echo "Code hash: "');
exec('cat codehash.txt');
