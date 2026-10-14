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
    pluginManager.withPlugin("com.android.library") {
        extensions
            .configure(
                com.android.build.api.variant.LibraryAndroidComponentsExtension::class.java,
            ) {
                finalizeDsl { extension ->
                    val appSdk =
                        rootProject
                            .project(":app")
                            .extensions
                            .findByType(
                                com.android.build.api.dsl.ApplicationExtension::class.java,
                            )
                            ?.compileSdk
                            ?: 36
                    if ((extension.compileSdk ?: 0) < appSdk) {
                        extension.compileSdk = appSdk
                    }
                }
            }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    if (name != "flutter_blue_plus") {
        return@subprojects
    }
    tasks.matching { it.name == "preBuild" }.configureEach {
        doFirst {
            val source =
                file(
                    "src/main/java/com/lib/flutter_blue_plus/FlutterBluePlusPlugin.java",
                )
            if (!source.exists()) {
                return@doFirst
            }
            val text = source.readText()
            val original = "scanner.startScan(filters, settings, getScanCallback());"
            if (!text.contains(original) || text.contains("filters.isEmpty()")) {
                return@doFirst
            }
            source.writeText(
                text.replace(
                    original,
                    """
                    if (filters.isEmpty()) {
                        scanner.startScan(null, settings, getScanCallback());
                    } else {
                        scanner.startScan(filters, settings, getScanCallback());
                    }
                    """.trimIndent(),
                ),
            )
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
