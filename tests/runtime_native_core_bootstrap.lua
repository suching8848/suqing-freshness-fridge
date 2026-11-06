require=function() return true end
SandboxVars={SuQingFreshnessFridge={Enabled=true,Capacity=200,RestoreHours=10,AllowRotten=true}}
NativeCoreClock=getGameTime():getWorldAgeHours()
function getTimestampMs() return 1793880000000 end
NativeCoreObject=ProbeObject
return "native Core bootstrap ready; no world created"
