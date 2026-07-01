import SwiftUI
import ComposableArchitecture

@Reducer
struct Tools {
    @ObservableState
    struct State {
        var networkingDisplayed: Bool = false
    }
    
    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case delegate(Delegate)
    }
    
    enum Delegate {
        case showNetworkingWindow(Bool)
    }
    
    var body: some ReducerOf<Self> {
        
        BindingReducer()
        
        Reduce { state, action in
            switch action {
            case .binding(\.networkingDisplayed):
                return .send(.delegate(.showNetworkingWindow(state.networkingDisplayed)))
            case .delegate:
                return .none
            default:
                return .none
            }
        }
    }
}

struct ToolsView: View {
    
    @Bindable var store: StoreOf<Tools>
    
    var body: some View {
        VStack {
            Text("Siminator by Mikolaj Zawada")

            Toggle(isOn: $store.networkingDisplayed) {
                Text("Show networking sidebar")
            }
            .toggleStyle(.switch)
            .tint(.gray)
        }
        .padding(16)
        .frame(width: 260, height: 180)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.regularMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}
