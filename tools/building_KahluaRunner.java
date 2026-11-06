import java.lang.reflect.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.Arrays;

/** Runs only supplied Lua files in an isolated Kahlua environment. */
public class building_KahluaRunner {
    public static void main(String[] args) throws Exception {
        Class<?> p=Class.forName("se.krka.kahlua.j2se.J2SEPlatform");
        Object platform=p.getConstructor().newInstance();
        Object env=p.getMethod("newEnvironment").invoke(platform);
        Class<?> table=Class.forName("se.krka.kahlua.vm.KahluaTable");
        Class<?> threadClass=Class.forName("se.krka.kahlua.vm.KahluaThread");
        Object thread=threadClass.getConstructor(Class.forName("se.krka.kahlua.vm.Platform"),table).newInstance(platform,env);
        threadClass.getField("debugOwnerThread").set(thread,Thread.currentThread());
        Method compile=Class.forName("se.krka.kahlua.luaj.compiler.LuaCompiler").getMethod("loadstring",String.class,String.class,table);
        Method run=threadClass.getMethod("pcall",Object.class,Object[].class);
        for (String path:args) {
            Object closure=compile.invoke(null,new String(Files.readAllBytes(Paths.get(path)),StandardCharsets.UTF_8),path,env);
            Object[] result=(Object[])run.invoke(thread,closure,new Object[0]);
            if (!Boolean.TRUE.equals(result[0])) throw new AssertionError(path+": "+Arrays.toString(result));
            if (result.length>1 && result[1] instanceof String && (result[1].toString().startsWith("BUILDING_") || result[1].toString().startsWith("CAPACITY_"))) {
                System.out.println(result[1]);
            }
        }
    }
}
