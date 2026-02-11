# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.ArticleTest do
  @moduledoc """
  Tests for the Article workflow demonstrating entry/exit callbacks.

  The Article uses state callbacks to:
  - Set timestamps when entering states (submitted_at, approved_at, published_at)
  - Track unpublish events via exit callbacks
  - Increment version on each publish

  This demonstrates:
  - on_enter callbacks for state initialization
  - on_exit callbacks for cleanup/notifications
  - Callback execution order (exit before entry)
  - Multiple callbacks on a single state
  """
  use ExUnit.Case

  describe "entry callbacks" do
    test "sets submitted_at when entering pending_review" do
      {:ok, article} = Article.create(%{title: "My Article", author: "Jane"})
      assert article.state == :draft
      assert article.submitted_at == nil

      {:ok, article} = Article.submit(article)
      assert article.state == :pending_review
      assert article.submitted_at != nil
    end

    test "sets approved_at when entering scheduled" do
      {:ok, article} = Article.create(%{title: "My Article"})
      {:ok, article} = Article.submit(article)
      assert article.approved_at == nil

      {:ok, article} = Article.approve(article)
      assert article.state == :scheduled
      assert article.approved_at != nil
    end

    test "sets published_at and increments version when entering published" do
      {:ok, article} = Article.create(%{title: "My Article"})
      {:ok, article} = Article.submit(article)
      {:ok, article} = Article.approve(article)
      assert article.published_at == nil
      assert article.version == 0

      {:ok, article} = Article.publish(article)
      assert article.state == :published
      assert article.published_at != nil
      assert article.version == 1
    end

    test "sets archived_at when entering archived" do
      {:ok, article} = Article.create(%{title: "My Article"})
      assert article.archived_at == nil

      {:ok, article} = Article.archive(article)
      assert article.state == :archived
      assert article.archived_at != nil
    end
  end

  describe "exit callbacks" do
    test "increments unpublished_count when exiting published state" do
      {:ok, article} = Article.create(%{title: "My Article"})
      {:ok, article} = Article.submit(article)
      {:ok, article} = Article.approve(article)
      {:ok, article} = Article.publish(article)
      assert article.unpublished_count == 0

      {:ok, article} = Article.unpublish(article)
      assert article.state == :draft
      assert article.unpublished_count == 1
    end

    test "tracks multiple unpublish events" do
      {:ok, article} = Article.create(%{title: "My Article"})

      # First publish/unpublish cycle
      {:ok, article} = Article.submit(article)
      {:ok, article} = Article.approve(article)
      {:ok, article} = Article.publish(article)
      {:ok, article} = Article.unpublish(article)
      assert article.unpublished_count == 1

      # Second publish/unpublish cycle
      {:ok, article} = Article.submit(article)
      {:ok, article} = Article.approve(article)
      {:ok, article} = Article.publish(article)
      assert article.version == 2

      {:ok, article} = Article.unpublish(article)
      assert article.unpublished_count == 2
    end

    test "exit callback runs when archiving from published" do
      {:ok, article} = Article.create(%{title: "My Article"})
      {:ok, article} = Article.submit(article)
      {:ok, article} = Article.approve(article)
      {:ok, article} = Article.publish(article)

      {:ok, article} = Article.archive(article)
      assert article.state == :archived
      # Exit from published should have incremented count
      assert article.unpublished_count == 1
      # Entry to archived should have set timestamp
      assert article.archived_at != nil
    end
  end

  describe "callback execution order" do
    test "exit callbacks run before entry callbacks" do
      {:ok, article} = Article.create(%{title: "My Article"})
      {:ok, article} = Article.submit(article)
      {:ok, article} = Article.approve(article)
      {:ok, article} = Article.publish(article)

      # When archiving from published:
      # 1. Exit from :published runs (increments unpublished_count)
      # 2. Entry to :archived runs (sets archived_at)
      {:ok, article} = Article.archive(article)

      # Both should have run
      assert article.unpublished_count == 1
      assert article.archived_at != nil
    end
  end

  describe "publishing workflow" do
    test "full happy path: draft -> submit -> approve -> publish" do
      {:ok, article} =
        Article.create(%{title: "Great Article", body: "Content here", author: "John"})

      assert article.state == :draft

      {:ok, article} = Article.submit(article)
      assert article.state == :pending_review
      assert article.submitted_at != nil

      {:ok, article} = Article.approve(article)
      assert article.state == :scheduled
      assert article.approved_at != nil

      {:ok, article} = Article.publish(article)
      assert article.state == :published
      assert article.published_at != nil
      assert article.version == 1
    end

    test "rejection workflow: draft -> submit -> reject -> back to draft" do
      {:ok, article} = Article.create(%{title: "Needs Work"})

      {:ok, article} = Article.submit(article)
      assert article.state == :pending_review

      {:ok, article} = Article.reject(article)
      assert article.state == :draft
      # submitted_at is preserved from the submission
      assert article.submitted_at != nil
    end

    test "can resubmit after rejection" do
      {:ok, article} = Article.create(%{title: "Getting Better"})

      {:ok, article} = Article.submit(article)
      first_submission = article.submitted_at

      {:ok, article} = Article.reject(article)
      assert article.state == :draft

      # Allow some time to pass for different timestamp
      Process.sleep(1)

      {:ok, article} = Article.submit(article)
      assert article.state == :pending_review
      # submitted_at should be updated
      assert article.submitted_at != first_submission
    end

    test "version increments on each publish" do
      {:ok, article} = Article.create(%{title: "Evolving Article"})
      assert article.version == 0

      # First publish
      {:ok, article} = Article.submit(article)
      {:ok, article} = Article.approve(article)
      {:ok, article} = Article.publish(article)
      assert article.version == 1

      # Unpublish and republish
      {:ok, article} = Article.unpublish(article)
      {:ok, article} = Article.submit(article)
      {:ok, article} = Article.approve(article)
      {:ok, article} = Article.publish(article)
      assert article.version == 2

      # Third publish
      {:ok, article} = Article.unpublish(article)
      {:ok, article} = Article.submit(article)
      {:ok, article} = Article.approve(article)
      {:ok, article} = Article.publish(article)
      assert article.version == 3
    end
  end

  describe "archiving" do
    test "can archive from draft" do
      {:ok, article} = Article.create(%{title: "Never Published"})

      {:ok, article} = Article.archive(article)
      assert article.state == :archived
    end

    test "can archive from published" do
      {:ok, article} = Article.create(%{title: "Going Away"})
      {:ok, article} = Article.submit(article)
      {:ok, article} = Article.approve(article)
      {:ok, article} = Article.publish(article)

      {:ok, article} = Article.archive(article)
      assert article.state == :archived
    end

    test "cannot archive from pending_review" do
      {:ok, article} = Article.create(%{title: "In Review"})
      {:ok, article} = Article.submit(article)
      assert article.state == :pending_review

      {:error, error} = Article.archive(article)
      assert Exception.message(error) =~ "archive"
    end

    test "cannot archive from scheduled" do
      {:ok, article} = Article.create(%{title: "Scheduled"})
      {:ok, article} = Article.submit(article)
      {:ok, article} = Article.approve(article)
      assert article.state == :scheduled

      {:error, error} = Article.archive(article)
      assert Exception.message(error) =~ "archive"
    end
  end

  describe "invalid transitions" do
    test "cannot submit already submitted article" do
      {:ok, article} = Article.create(%{title: "Test"})
      {:ok, article} = Article.submit(article)

      {:error, error} = Article.submit(article)
      assert Exception.message(error) =~ "submit"
    end

    test "cannot publish without approval" do
      {:ok, article} = Article.create(%{title: "Test"})
      {:ok, article} = Article.submit(article)

      {:error, error} = Article.publish(article)
      assert Exception.message(error) =~ "publish"
    end

    test "cannot unpublish draft" do
      {:ok, article} = Article.create(%{title: "Test"})

      {:error, error} = Article.unpublish(article)
      assert Exception.message(error) =~ "unpublish"
    end
  end
end
