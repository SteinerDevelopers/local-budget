allprojects {
    repositories {
        google()
        mavenCentral()
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

// Legacy plugins (e.g. receive_sharing_intent 1.8.1) declare no compileOptions
// and carry their own KGP 1.9.22 on their buildscript classpath, so AGP floors
// their javac at 11 while Kotlin defaults to the running JDK (21) — the KGP
// JVM-target validation fails (pipelines 44/46/47). Best effort per module:
// KGP 2.x tasks follow their own compileDebugJavaWithJavac target through the
// lazy compilerOptions.jvmTarget provider; KGP 1.x tasks get kotlinOptions
// patched in doFirst (its getCompilerOptions DSL only arrived in KGP 2.0).
// kotlin.jvm.target.validation.mode=warning in gradle.properties is the
// backstop if neither reflection shape matches. No afterEvaluate — Flutter's
// evaluationDependsOn(":app") can evaluate projects before this block reaches
// them — and no AGP/KGP imports, since neither plugin is on this script's
// compile classpath.
fun javacLegacyNameFor(javac: JavaCompile?): String? =
    when (javac?.targetCompatibility) {
        "1.8" -> "1.8"
        "11" -> "11"
        "17" -> "17"
        "21" -> "21"
        else -> null
    }

fun alignViaCompilerOptions(task: Task): Boolean =
    runCatching {
        val loader = task.javaClass.classLoader
        val options = task.javaClass.getMethod("getCompilerOptions").invoke(task)
        val jvmTarget = options.javaClass.getMethod("getJvmTarget").invoke(options)
        val enumClass =
            Class.forName("org.jetbrains.kotlin.gradle.dsl.JvmTarget", false, loader)
        val current = jvmTarget.javaClass.getMethod("get").invoke(jvmTarget)
        val project = task.project
        val mapped =
            project.providers
                .provider {
                    val javac =
                        project.tasks.findByName("compileDebugJavaWithJavac") as? JavaCompile
                    javacLegacyNameFor(javac)
                        ?.let { name ->
                            val kotlinName =
                                if (name == "1.8") "JVM_1_8" else "JVM_$name"
                            enumClass.getMethod("valueOf", String::class.java).invoke(null, kotlinName)
                        }
                }.map { it ?: current }
        val providerClass = Class.forName("org.gradle.api.provider.Provider", false, loader)
        jvmTarget.javaClass.getMethod("set", providerClass).invoke(jvmTarget, mapped)
    }.isSuccess

fun alignKotlinJvmTarget(task: Task) {
    if (alignViaCompilerOptions(task)) return
    runCatching {
        val options = task.javaClass.getMethod("getKotlinOptions").invoke(task)
        val setter =
            options.javaClass.methods.first {
                it.name == "setJvmTarget" && it.parameterCount == 1
            }
        val project = task.project
        task.doFirst {
            runCatching {
                val javac =
                    project.tasks.findByName("compileDebugJavaWithJavac") as? JavaCompile
                javacLegacyNameFor(javac)?.let { setter.invoke(options, it) }
            }
        }
    }
}

subprojects {
    pluginManager.withPlugin("org.jetbrains.kotlin.android") {
        tasks.configureEach {
            val name = javaClass.simpleName
            if (name == "KotlinCompile" || name == "KotlinJvmCompile") {
                alignKotlinJvmTarget(this)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
