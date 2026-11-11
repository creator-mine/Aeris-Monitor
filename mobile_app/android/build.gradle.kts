allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Some plugins still default to an older compileSdk. Force 36 for every
// Android module so AAR metadata checks (flutter_plugin_android_lifecycle)
// pass. Reflection avoids a compile-time dependency on AGP types here.
// Registered before any project is evaluated.
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android") ?: return@afterEvaluate
        val cls = androidExt.javaClass
        val byMethod = cls.methods.firstOrNull {
            it.name == "compileSdkVersion" &&
                it.parameterTypes.size == 1 &&
                it.parameterTypes[0] == Int::class.javaPrimitiveType
        }
        if (byMethod != null) {
            byMethod.invoke(androidExt, 36)
        } else {
            cls.methods.firstOrNull {
                it.name == "setCompileSdk" &&
                    it.parameterTypes.size == 1 &&
                    it.parameterTypes[0] == Int::class.javaPrimitiveType
            }?.invoke(androidExt, 36)
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
