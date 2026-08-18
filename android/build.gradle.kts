allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val externalBuildPath = System.getenv("MORNING_ATTENDANCE_BUILD_DIR")
val newBuildDir: Directory = if (externalBuildPath.isNullOrBlank()) {
    rootProject.layout.buildDirectory.dir("../../build").get()
} else {
    rootProject.layout.dir(providers.provider { file(externalBuildPath) }).get()
}
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
