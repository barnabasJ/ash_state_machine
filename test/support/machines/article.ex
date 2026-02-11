# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule Article do
  @moduledoc """
  A content management article with publishing workflow.

  Demonstrates:
  - Entry callbacks (on_enter) for state lifecycle events
  - Exit callbacks (on_exit) for cleanup/notifications
  - Automatic timestamp management
  - Complex multi-state workflows

  ## Workflow

  draft -> pending_review -> scheduled -> published
           |                              |
           v                              v
         draft (rejected)               draft (unpublished)
           |                              |
           +------> archived <------------+
  """
  use Ash.Resource,
    domain: Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshStateMachine]

  state_machine do
    initial_states [:draft]
    default_initial_state :draft

    states do
      state :pending_review do
        on_enter([{Article.SetTimestamp, field: :submitted_at}])
      end

      state :scheduled do
        on_enter([{Article.SetTimestamp, field: :approved_at}])
      end

      state :published do
        on_enter([
          {Article.SetTimestamp, field: :published_at},
          {Article.IncrementVersion, []}
        ])

        on_exit([{Article.RecordUnpublish, []}])
      end

      state :archived do
        on_enter([{Article.SetTimestamp, field: :archived_at}])
      end
    end

    transitions do
      # Submit for review
      transition :submit, from: :draft, to: :pending_review, require_atomic?: false

      # Approve or reject review
      transition :approve, from: :pending_review, to: :scheduled, require_atomic?: false
      transition :reject, from: :pending_review, to: :draft, require_atomic?: false

      # Publish
      transition :publish, from: :scheduled, to: :published, require_atomic?: false

      # Unpublish back to draft
      transition :unpublish, from: :published, to: :draft, require_atomic?: false

      # Archive from draft or published
      transition :archive, from: [:draft, :published], to: :archived, require_atomic?: false
    end
  end

  actions do
    default_accept :*
    defaults [:read]

    create :create do
      accept [:title, :body, :author]
    end

    update :submit do
      require_atomic? false
    end

    update :approve do
      require_atomic? false
    end

    update :reject do
      require_atomic? false
    end

    update :publish do
      require_atomic? false
    end

    update :unpublish do
      require_atomic? false
    end

    update :archive do
      require_atomic? false
    end
  end

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string, public?: true
    attribute :body, :string, public?: true
    attribute :author, :string, public?: true
    attribute :version, :integer, default: 0, public?: true

    # Timestamp attributes set by entry callbacks
    attribute :submitted_at, :utc_datetime_usec, public?: true
    attribute :approved_at, :utc_datetime_usec, public?: true
    attribute :published_at, :utc_datetime_usec, public?: true
    attribute :archived_at, :utc_datetime_usec, public?: true

    # Exit callback tracking
    attribute :unpublished_count, :integer, default: 0, public?: true
  end

  code_interface do
    define :create
    define :submit
    define :approve
    define :reject
    define :publish
    define :unpublish
    define :archive
  end

  # Custom change modules for callbacks
  defmodule SetTimestamp do
    @moduledoc "Sets a timestamp field to current UTC time"
    use Ash.Resource.Change

    def change(changeset, opts, _context) do
      field = opts[:field]
      Ash.Changeset.force_change_attribute(changeset, field, DateTime.utc_now())
    end
  end

  defmodule IncrementVersion do
    @moduledoc "Increments the version number on publish"
    use Ash.Resource.Change

    def change(changeset, _opts, _context) do
      current = Ash.Changeset.get_attribute(changeset, :version) || 0
      Ash.Changeset.force_change_attribute(changeset, :version, current + 1)
    end
  end

  defmodule RecordUnpublish do
    @moduledoc "Records when an article is unpublished (exit callback)"
    use Ash.Resource.Change

    def change(changeset, _opts, _context) do
      count = Ash.Changeset.get_attribute(changeset, :unpublished_count) || 0
      Ash.Changeset.force_change_attribute(changeset, :unpublished_count, count + 1)
    end
  end
end
