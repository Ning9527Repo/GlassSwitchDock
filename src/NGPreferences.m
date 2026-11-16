#import "Bridge.h"

static BOOL gNGSwitchEnabled = YES;
static BOOL gNGDockEnabled = YES;
static NSInteger gNGSwitchStyle = 0;
static NSInteger gNGDockStyle = 0;

void NGPreferencesReload(void) {
    NSDictionary *data = NGReadPreferences();
    id sw = data[@"enabledSwitch"], dk = data[@"enabledDock"];
    gNGSwitchEnabled = [sw isKindOfClass:NSNumber.class] ? [sw boolValue] : YES;
    gNGDockEnabled = [dk isKindOfClass:NSNumber.class] ? [dk boolValue] : YES;
    gNGSwitchStyle = [data[@"switchStyle"] integerValue] == 1 ? 1 : 0;
    gNGDockStyle = [data[@"dockStyle"] integerValue] == 1 ? 1 : 0;
}
BOOL NGSwitchEnabled(void) { return gNGSwitchEnabled; }
BOOL NGDockEnabled(void) { return gNGDockEnabled; }
NSInteger NGSwitchStyle(void) { return gNGSwitchStyle; }
NSInteger NGDockStyle(void) { return gNGDockStyle; }
void NGRefreshAll(void) { NGRefreshAllSwitches(); NGRefreshDocks(); }
