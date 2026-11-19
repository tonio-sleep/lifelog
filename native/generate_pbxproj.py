from pathlib import Path

ROOT = Path(__file__).parent
APP = ROOT / "Lifelog"

swift_files = sorted(p for p in APP.rglob("*.swift"))
assert swift_files, "No Swift files found"
TEST_APP = ROOT / "LifelogTests"
test_files = sorted(TEST_APP.rglob("*.swift"))

counter = 0
def new_id():
    global counter
    counter += 1
    return f"{counter:024X}"

PROJECT = new_id()
TARGET = new_id()
PRODUCT_REF = new_id()
PROJECT_LIST = new_id()
TARGET_LIST = new_id()
BUILD_SOURCE = new_id()
BUILD_RESOURCE = new_id()
BUILD_FRAMEWORK = new_id()
GROUP_ROOT = new_id()
GROUP_APP = new_id()
GROUP_CORE = new_id()
GROUP_DOMAIN = new_id()
GROUP_INTEGRATIONS = new_id()
GROUP_UI = new_id()
GROUP_RESOURCES = new_id()
GROUP_PRODUCTS = new_id()
ASSETS_REF = new_id()
ASSETS_BUILD = new_id()
INFOPLIST_REF = new_id()
ENTITLEMENTS_REF = new_id()
CONFIG_PROJECT_DEBUG = new_id()
CONFIG_PROJECT_RELEASE = new_id()
CONFIG_TARGET_DEBUG = new_id()
CONFIG_TARGET_RELEASE = new_id()
TEST_TARGET = new_id()
TEST_PRODUCT_REF = new_id()
TEST_PRODUCT_LIST = new_id()
TEST_SOURCE = new_id()
TEST_FRAMEWORK = new_id()
TEST_GROUP = new_id()
TEST_PROXY = new_id()
TEST_DEPENDENCY = new_id()
CONFIG_TEST_DEBUG = new_id()
CONFIG_TEST_RELEASE = new_id()

file_ids = {}
build_ids = {}
for path in swift_files:
    file_ids[path] = new_id()
    build_ids[path] = new_id()
for path in test_files:
    file_ids[path] = new_id()
    build_ids[path] = new_id()

def q(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'

def rel(path):
    return path.relative_to(APP).as_posix()

lines = []
def out(s=""):
    lines.append(s)

out("// !$*UTF8*$!")
out("{")
out("\tarchiveVersion = 1;")
out("\tclasses = {")
out("\t};")
out("\tobjectVersion = 56;")
out("\tobjects = {")

out("/* Begin PBXBuildFile section */")
for path in swift_files:
    out(f"\t\t{build_ids[path]} /* {path.name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ids[path]} /* {path.name} */; }};")
for path in test_files:
    out(f"\t\t{build_ids[path]} /* {path.name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ids[path]} /* {path.name} */; }};")
out(f"\t\t{ASSETS_BUILD} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {ASSETS_REF} /* Assets.xcassets */; }};")
out("/* End PBXBuildFile section */")

out("")
out("/* Begin PBXFileReference section */")
out(f"\t\t{PRODUCT_REF} /* Lifelog.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Lifelog.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
out(f"\t\t{ASSETS_REF} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = \"<group>\"; }};")
out(f"\t\t{INFOPLIST_REF} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};")
out(f"\t\t{ENTITLEMENTS_REF} /* Lifelog.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = Lifelog.entitlements; sourceTree = \"<group>\"; }};")
for path in swift_files:
    out(f"\t\t{file_ids[path]} /* {path.name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(path.name)}; sourceTree = \"<group>\"; }};")
out(f"\t\t{TEST_PRODUCT_REF} /* LifelogTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = LifelogTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};")
for path in test_files:
    out(f"\t\t{file_ids[path]} /* {path.name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(path.name)}; sourceTree = \"<group>\"; }};")
out("/* End PBXFileReference section */")

out("")
out("/* Begin PBXFrameworksBuildPhase section */")
out(f"\t\t{BUILD_FRAMEWORK} /* Frameworks */ = {{")
out("\t\t\tisa = PBXFrameworksBuildPhase;")
out("\t\t\tbuildActionMask = 2147483647;")
out("\t\t\tfiles = (")
out("\t\t\t);")
out("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
out("\t\t};")
out(f"\t\t{TEST_FRAMEWORK} /* Frameworks */ = {{")
out("\t\t\tisa = PBXFrameworksBuildPhase;")
out("\t\t\tbuildActionMask = 2147483647;")
out("\t\t\tfiles = (")
out("\t\t\t);")
out("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
out("\t\t};")
out("/* End PBXFrameworksBuildPhase section */")

out("")
out("/* Begin PBXGroup section */")
out(f"\t\t{GROUP_ROOT} = {{")
out("\t\t\tisa = PBXGroup;")
out(f"\t\t\tchildren = ({GROUP_APP}, {TEST_GROUP}, {GROUP_PRODUCTS},);")
out("\t\t\tsourceTree = \"<group>\";")
out("\t\t};")
out(f"\t\t{GROUP_APP} /* Lifelog */ = {{")
out("\t\t\tisa = PBXGroup;")
out(f"\t\t\tchildren = ({GROUP_CORE}, {GROUP_DOMAIN}, {GROUP_INTEGRATIONS}, {GROUP_UI}, {GROUP_RESOURCES}, {INFOPLIST_REF}, {ENTITLEMENTS_REF}, {file_ids[APP / 'LifelogAppDelegate.swift']}, {file_ids[APP / 'LifelogApp.swift']},);")
out("\t\t\tpath = Lifelog;")
out("\t\t\tsourceTree = \"<group>\";")
out("\t\t};")
group_defs = [
    (GROUP_CORE, "Core", "Core", ["Core"]),
    (GROUP_DOMAIN, "Domain", "Domain", ["Domain"]),
    (GROUP_INTEGRATIONS, "Integrations", "Integrations", ["Integrations"]),
    (GROUP_UI, "UI", "UI", ["UI"]),
]
for gid, comment, path, prefix in group_defs:
    children = [file_ids[p] for p in swift_files if p.relative_to(APP).parts[0] == path]
    out(f"\t\t{gid} /* {comment} */ = {{")
    out("\t\t\tisa = PBXGroup;")
    out("\t\t\tchildren = (" + ", ".join(children) + ",);")
    out(f"\t\t\tpath = {path};")
    out("\t\t\tsourceTree = \"<group>\";")
    out("\t\t};")
out(f"\t\t{TEST_GROUP} /* LifelogTests */ = {{")
out("\t\t\tisa = PBXGroup;")
out("\t\t\tchildren = (" + ", ".join(file_ids[p] for p in test_files) + ",);")
out("\t\t\tpath = LifelogTests;")
out("\t\t\tsourceTree = \"<group>\";")
out("\t\t};")
out(f"\t\t{GROUP_RESOURCES} /* Resources */ = {{")
out("\t\t\tisa = PBXGroup;")
out(f"\t\t\tchildren = ({ASSETS_REF},);")
out("\t\t\tname = Resources;")
out("\t\t\tsourceTree = \"<group>\";")
out("\t\t};")
out(f"\t\t{GROUP_PRODUCTS} /* Products */ = {{")
out("\t\t\tisa = PBXGroup;")
out(f"\t\t\tchildren = ({PRODUCT_REF}, {TEST_PRODUCT_REF},);")
out("\t\t\tname = Products;")
out("\t\t\tsourceTree = \"<group>\";")
out("\t\t};")
out("/* End PBXGroup section */")

out("")
out("/* Begin PBXNativeTarget section */")
out(f"\t\t{TARGET} /* Lifelog */ = {{")
out("\t\t\tisa = PBXNativeTarget;")
out(f"\t\t\tbuildConfigurationList = {TARGET_LIST} /* Build configuration list for PBXNativeTarget \"Lifelog\" */;")
out("\t\t\tbuildPhases = (")
out(f"\t\t\t\t{BUILD_SOURCE} /* Sources */,")
out(f"\t\t\t\t{BUILD_FRAMEWORK} /* Frameworks */,")
out(f"\t\t\t\t{BUILD_RESOURCE} /* Resources */,")
out("\t\t\t);")
out("\t\t\tbuildRules = (")
out("\t\t\t);")
out("\t\t\tdependencies = (")
out("\t\t\t);")
out("\t\t\tname = Lifelog;")
out("\t\t\tproductName = Lifelog;")
out(f"\t\t\tproductReference = {PRODUCT_REF} /* Lifelog.app */;")
out("\t\t\tproductType = \"com.apple.product-type.application\";")
out("\t\t};")
out(f"\t\t{TEST_TARGET} /* LifelogTests */ = {{")
out("\t\t\tisa = PBXNativeTarget;")
out(f"\t\t\tbuildConfigurationList = {TEST_PRODUCT_LIST} /* Build configuration list for PBXNativeTarget \"LifelogTests\" */;")
out("\t\t\tbuildPhases = (")
out(f"\t\t\t\t{TEST_SOURCE} /* Sources */,")
out(f"\t\t\t\t{TEST_FRAMEWORK} /* Frameworks */,")
out("\t\t\t);")
out("\t\t\tbuildRules = (")
out("\t\t\t);")
out("\t\t\tdependencies = (")
out(f"\t\t\t\t{TEST_DEPENDENCY} /* PBXTargetDependency */,")
out("\t\t\t);")
out("\t\t\tname = LifelogTests;")
out("\t\t\tproductName = LifelogTests;")
out(f"\t\t\tproductReference = {TEST_PRODUCT_REF} /* LifelogTests.xctest */;")
out("\t\t\tproductType = \"com.apple.product-type.bundle.unit-test\";")
out("\t\t};")
out("/* End PBXNativeTarget section */")

out("")
out("/* Begin PBXContainerItemProxy section */")
out(f"\t\t{TEST_PROXY} /* PBXContainerItemProxy */ = {{")
out("\t\t\tisa = PBXContainerItemProxy;")
out(f"\t\t\tcontainerPortal = {PROJECT} /* Project object */;")
out("\t\t\tproxyType = 1;")
out(f"\t\t\tremoteGlobalIDString = {TARGET};")
out("\t\t\tremoteInfo = Lifelog;")
out("\t\t};")
out("/* End PBXContainerItemProxy section */")

out("")
out("/* Begin PBXTargetDependency section */")
out(f"\t\t{TEST_DEPENDENCY} /* PBXTargetDependency */ = {{")
out("\t\t\tisa = PBXTargetDependency;")
out(f"\t\t\ttarget = {TARGET} /* Lifelog */;")
out(f"\t\t\ttargetProxy = {TEST_PROXY} /* PBXContainerItemProxy */;")
out("\t\t};")
out("/* End PBXTargetDependency section */")

out("")
out("/* Begin PBXProject section */")
out(f"\t\t{PROJECT} /* Project object */ = {{")
out("\t\t\tisa = PBXProject;")
out("\t\t\tattributes = {")
out("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
out("\t\t\t\tLastSwiftUpdateCheck = 1600;")
out("\t\t\t\tLastUpgradeCheck = 1600;")
out("\t\t\t\tTargetAttributes = {")
out(f"\t\t\t\t\t{TARGET} = {{")
out("\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;")
out("\t\t\t\t\t};")
out(f"\t\t\t\t\t{TEST_TARGET} = {{")
out("\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;")
out(f"\t\t\t\t\t\tTestTargetID = {TARGET};")
out("\t\t\t\t\t};")
out("\t\t\t\t};")
out("\t\t\t};")
out(f"\t\t\tbuildConfigurationList = {PROJECT_LIST} /* Build configuration list for PBXProject \"Lifelog\" */;")
out("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
out("\t\t\tdevelopmentRegion = en;")
out("\t\t\thasScannedForEncodings = 0;")
out("\t\t\tknownRegions = (")
out("\t\t\t\ten,")
out("\t\t\t\tBase,")
out("\t\t\t);")
out(f"\t\t\tmainGroup = {GROUP_ROOT};")
out(f"\t\t\tproductRefGroup = {GROUP_PRODUCTS} /* Products */;")
out("\t\t\tprojectDirPath = \"\";")
out("\t\t\tprojectRoot = \"\";")
out("\t\t\ttargets = (")
out(f"\t\t\t\t{TARGET} /* Lifelog */,")
out(f"\t\t\t\t{TEST_TARGET} /* LifelogTests */,")
out("\t\t\t);")
out("\t\t};")
out("/* End PBXProject section */")

out("")
out("/* Begin PBXResourcesBuildPhase section */")
out(f"\t\t{BUILD_RESOURCE} /* Resources */ = {{")
out("\t\t\tisa = PBXResourcesBuildPhase;")
out("\t\t\tbuildActionMask = 2147483647;")
out(f"\t\t\tfiles = ({ASSETS_BUILD} /* Assets.xcassets in Resources */,);")
out("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
out("\t\t};")
out("/* End PBXResourcesBuildPhase section */")

out("")
out("/* Begin PBXSourcesBuildPhase section */")
out(f"\t\t{BUILD_SOURCE} /* Sources */ = {{")
out("\t\t\tisa = PBXSourcesBuildPhase;")
out("\t\t\tbuildActionMask = 2147483647;")
out("\t\t\tfiles = (")
for path in swift_files:
    out(f"\t\t\t\t{build_ids[path]} /* {path.name} in Sources */,")
out("\t\t\t);")
out("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
out("\t\t};")
out(f"\t\t{TEST_SOURCE} /* Sources */ = {{")
out("\t\t\tisa = PBXSourcesBuildPhase;")
out("\t\t\tbuildActionMask = 2147483647;")
out("\t\t\tfiles = (")
for path in test_files:
    out(f"\t\t\t\t{build_ids[path]} /* {path.name} in Sources */,")
out("\t\t\t);")
out("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
out("\t\t};")
out("/* End PBXSourcesBuildPhase section */")

out("")
out("/* Begin XCBuildConfiguration section */")
common_project = [
    "ALWAYS_SEARCH_USER_PATHS = NO;",
    "CLANG_ENABLE_MODULES = YES;",
    "CLANG_ENABLE_OBJC_ARC = YES;",
    "ENABLE_STRICT_OBJC_MSGSEND = YES;",
    "GCC_NO_COMMON_BLOCKS = YES;",
    "IPHONEOS_DEPLOYMENT_TARGET = 17.0;",
    "SDKROOT = iphoneos;",
    "SWIFT_VERSION = 5.0;",
]
target_settings = [
    "ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;",
    "CODE_SIGN_ENTITLEMENTS = Lifelog/Lifelog.entitlements;",
    "CODE_SIGN_STYLE = Automatic;",
    "CURRENT_PROJECT_VERSION = 1;",
    "GENERATE_INFOPLIST_FILE = NO;",
    "INFOPLIST_FILE = Lifelog/Info.plist;",
    "MARKETING_VERSION = 1.0;",
    "PRODUCT_BUNDLE_IDENTIFIER = com.logginglife.lifelog;",
    "PRODUCT_NAME = \"$(TARGET_NAME)\";",
    "SWIFT_EMIT_LOC_STRINGS = YES;",
    "TARGETED_DEVICE_FAMILY = \"1,2\";",
]
test_settings = [
    "BUNDLE_LOADER = \"$(TEST_HOST)\";",
    "CODE_SIGN_STYLE = Automatic;",
    "GENERATE_INFOPLIST_FILE = YES;",
    "IPHONEOS_DEPLOYMENT_TARGET = 17.0;",
    "LD_RUNPATH_SEARCH_PATHS = \"$(inherited) @executable_path/Frameworks @loader_path/Frameworks\";",
    "PRODUCT_BUNDLE_IDENTIFIER = com.logginglife.lifelog.tests;",
    "PRODUCT_NAME = \"$(TARGET_NAME)\";",
    "SDKROOT = iphoneos;",
    "SWIFT_VERSION = 5.0;",
    "TARGETED_DEVICE_FAMILY = \"1,2\";",
    "TEST_HOST = \"$(BUILT_PRODUCTS_DIR)/Lifelog.app/Lifelog\";",
]
configs = [
    (CONFIG_PROJECT_DEBUG, "Debug", common_project, True),
    (CONFIG_PROJECT_RELEASE, "Release", common_project, False),
    (CONFIG_TARGET_DEBUG, "Debug", target_settings, True),
    (CONFIG_TARGET_RELEASE, "Release", target_settings, False),
    (CONFIG_TEST_DEBUG, "Debug", test_settings, True),
    (CONFIG_TEST_RELEASE, "Release", test_settings, False),
]
for cid, name, settings, is_debug in configs:
    out(f"\t\t{cid} /* {name} */ = {{")
    out("\t\t\tisa = XCBuildConfiguration;")
    out("\t\t\tbuildSettings = {")
    for setting in settings:
        out(f"\t\t\t\t{setting}")
    if is_debug:
        out("\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;")
        out("\t\t\t\tENABLE_TESTABILITY = YES;")
        out("\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;")
        out("\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (\"DEBUG=1\", \"$(inherited)\",);")
        out("\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;")
        out("\t\t\t\tONLY_ACTIVE_ARCH = YES;")
        out("\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;")
        out("\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";")
    else:
        out("\t\t\t\tDEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\";")
        out("\t\t\t\tENABLE_NS_ASSERTIONS = NO;")
        out("\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;")
        out("\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;")
        out("\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-O\";")
        out("\t\t\t\tVALIDATE_PRODUCT = YES;")
    out("\t\t\t};")
    out(f"\t\t\tname = {name};")
    out("\t\t};")
out("/* End XCBuildConfiguration section */")

out("")
out("/* Begin XCConfigurationList section */")
out(f"\t\t{PROJECT_LIST} /* Build configuration list for PBXProject \"Lifelog\" */ = {{")
out("\t\t\tisa = XCConfigurationList;")
out(f"\t\t\tbuildConfigurations = ({CONFIG_PROJECT_DEBUG} /* Debug */, {CONFIG_PROJECT_RELEASE} /* Release */,);")
out("\t\t\tdefaultConfigurationIsVisible = 0;")
out(f"\t\t\tdefaultConfigurationName = Release;")
out("\t\t};")
out(f"\t\t{TARGET_LIST} /* Build configuration list for PBXNativeTarget \"Lifelog\" */ = {{")
out("\t\t\tisa = XCConfigurationList;")
out(f"\t\t\tbuildConfigurations = ({CONFIG_TARGET_DEBUG} /* Debug */, {CONFIG_TARGET_RELEASE} /* Release */,);")
out("\t\t\tdefaultConfigurationIsVisible = 0;")
out(f"\t\t\tdefaultConfigurationName = Release;")
out("\t\t};")
out(f"\t\t{TEST_PRODUCT_LIST} /* Build configuration list for PBXNativeTarget \"LifelogTests\" */ = {{")
out("\t\t\tisa = XCConfigurationList;")
out(f"\t\t\tbuildConfigurations = ({CONFIG_TEST_DEBUG} /* Debug */, {CONFIG_TEST_RELEASE} /* Release */,);")
out("\t\t\tdefaultConfigurationIsVisible = 0;")
out(f"\t\t\tdefaultConfigurationName = Release;")
out("\t\t};")
out("/* End XCConfigurationList section */")
out("\t};")
out(f"\trootObject = {PROJECT} /* Project object */;")
out("}")

(ROOT / "Lifelog.xcodeproj").mkdir(exist_ok=True)
(ROOT / "Lifelog.xcodeproj" / "project.pbxproj").write_text("\n".join(lines) + "\n", encoding="utf-8")

# Shared schemes let xcodebuild find both targets on a clean CI checkout.
app_ref = (
    f'<BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{TARGET}" '
    f'BuildableName = "Lifelog.app" BlueprintName = "Lifelog" '
    f'ReferencedContainer = "container:Lifelog.xcodeproj"></BuildableReference>'
)
test_ref = (
    f'<BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{TEST_TARGET}" '
    f'BuildableName = "LifelogTests.xctest" BlueprintName = "LifelogTests" '
    f'ReferencedContainer = "container:Lifelog.xcodeproj"></BuildableReference>'
)

app_scheme = f'''<?xml version = "1.0" encoding = "UTF-8"?>
<Scheme LastUpgradeVersion = "1600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            {app_ref}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.IDEFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         {app_ref}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         {app_ref}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug"/>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"/>
</Scheme>
'''

test_scheme = f'''<?xml version = "1.0" encoding = "UTF-8"?>
<Scheme LastUpgradeVersion = "1600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "NO" buildForProfiling = "NO" buildForArchiving = "NO" buildForAnalyzing = "YES">
            {app_ref}
         </BuildActionEntry>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "NO" buildForAnalyzing = "YES">
            {test_ref}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference skipped = "NO">
            {test_ref}
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.IDEFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         {app_ref}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         {app_ref}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug"/>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"/>
</Scheme>
'''

schemes_dir = ROOT / "Lifelog.xcodeproj" / "xcshareddata" / "xcschemes"
schemes_dir.mkdir(parents=True, exist_ok=True)
(schemes_dir / "Lifelog.xcscheme").write_text(app_scheme, encoding="utf-8")
(schemes_dir / "LifelogTests.xcscheme").write_text(test_scheme, encoding="utf-8")

print(f"Generated project with {len(swift_files)} Swift files and {len(test_files)} test files")
