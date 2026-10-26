defmodule AshStateMachine.NamedPrimaryCreateTest.Resource do
  @moduledoc false
  use Ash.Resource,
    domain: AshStateMachine.NamedPrimaryCreateTest.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshStateMachine]

  state_machine do
    initial_states([:open])
    default_initial_state(:open)
  end

  actions do
    create :provision do
      primary?(true)
      accept([])
    end
  end

  attributes do
    uuid_primary_key(:id)
  end
end

defmodule AshStateMachine.NamedPrimaryCreateTest.Domain do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource(AshStateMachine.NamedPrimaryCreateTest.Resource)
  end
end

defmodule AshStateMachine.NamedPrimaryCreateTest do
  use ExUnit.Case, async: true
  alias AshStateMachine.NamedPrimaryCreateTest.Resource

  @tag story: "US-NPC-01"
  test "a named primary create action remains the only create action and initializes state" do
    assert [%{name: :provision, primary?: true}] =
             Resource |> Ash.Resource.Info.actions() |> Enum.filter(&(&1.type == :create))

    assert {:ok, %{state: :open}} = Ash.create(Resource, %{}, action: :provision)
  end
end
