import java.lang.reflect.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.Arrays;

/** TEST ONLY: reuse the existing no-World native host, add a read-only field oracle. */
public final class capacity_refresh_NativeProbe {
    public static void main(String[] args)throws Exception {
        if(args.length<2)throw new IllegalArgumentException("setup Lua files and final cases required");
        runtime_NativeShieldProbe.main(Arrays.copyOf(args,args.length-1));
        Class<?> manager=Class.forName("zombie.Lua.LuaManager");
        Object env=manager.getField("env").get(null),thread=manager.getField("thread").get(null);
        Class<?> table=Class.forName("se.krka.kahlua.vm.KahluaTable"),fn=Class.forName("se.krka.kahlua.vm.JavaFunction");
        Field capacity=Class.forName("zombie.inventory.ItemContainer").getDeclaredField("capacity");capacity.setAccessible(true);
        Object read=Proxy.newProxyInstance(fn.getClassLoader(),new Class<?>[]{fn},(proxy,method,values)->{
            if(method.getName().equals("call")){
                Object frame=values[0];Object container=frame.getClass().getMethod("get",int.class).invoke(frame,0);
                return frame.getClass().getMethod("push",Object.class).invoke(frame,Double.valueOf(capacity.getInt(container)));
            }
            if(method.getName().equals("toString"))return "read-only native capacity field oracle";
            return null;
        });
        table.getMethod("rawset",Object.class,Object.class).invoke(env,"ProbeRawCapacity",read);
        String file=args[args.length-1];String source=new String(Files.readAllBytes(Paths.get(file)),StandardCharsets.UTF_8);
        Object closure=Class.forName("se.krka.kahlua.luaj.compiler.LuaCompiler").getMethod("loadstring",String.class,String.class,table).invoke(null,source,file,env);
        Object[] result=(Object[])thread.getClass().getMethod("pcall",Object.class,Object[].class).invoke(thread,closure,new Object[0]);
        System.out.println(file+": "+Arrays.toString(result));
        if(!Boolean.TRUE.equals(result[0]))throw new AssertionError("capacity refresh native regression failed: "+Arrays.toString(result));
    }
}
