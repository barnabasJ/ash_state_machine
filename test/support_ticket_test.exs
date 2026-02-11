# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshStateMachine.SupportTicketTest do
  @moduledoc """
  Tests for the SupportTicket workflow demonstrating transition guards.

  The SupportTicket uses guards to route tickets based on priority:
  - Priority 8-10: Escalated immediately
  - Priority 5-7: High priority queue
  - Priority 1-4: Standard queue

  This demonstrates:
  - Guard conditions on transitions
  - Multiple transitions for the same action with different outcomes
  - Fallback transitions when no guard matches
  - Full ticket lifecycle
  """
  use ExUnit.Case

  describe "priority-based triage with guards" do
    test "critical priority (9) routes to escalated" do
      {:ok, ticket} = SupportTicket.create(%{title: "System down", priority: 9})
      assert ticket.state == :new

      {:ok, ticket} = SupportTicket.triage(ticket)
      assert ticket.state == :escalated
    end

    test "high priority (6) routes to high_priority queue" do
      {:ok, ticket} = SupportTicket.create(%{title: "Feature broken", priority: 6})
      assert ticket.state == :new

      {:ok, ticket} = SupportTicket.triage(ticket)
      assert ticket.state == :high_priority
    end

    test "standard priority (3) routes to standard queue" do
      {:ok, ticket} = SupportTicket.create(%{title: "Question about feature", priority: 3})
      assert ticket.state == :new

      {:ok, ticket} = SupportTicket.triage(ticket)
      assert ticket.state == :standard
    end

    test "boundary: priority 8 goes to escalated (first guard)" do
      {:ok, ticket} = SupportTicket.create(%{priority: 8})
      {:ok, ticket} = SupportTicket.triage(ticket)
      assert ticket.state == :escalated
    end

    test "boundary: priority 7 goes to high_priority (second guard)" do
      {:ok, ticket} = SupportTicket.create(%{priority: 7})
      {:ok, ticket} = SupportTicket.triage(ticket)
      assert ticket.state == :high_priority
    end

    test "boundary: priority 5 goes to high_priority" do
      {:ok, ticket} = SupportTicket.create(%{priority: 5})
      {:ok, ticket} = SupportTicket.triage(ticket)
      assert ticket.state == :high_priority
    end

    test "boundary: priority 4 goes to standard (fallback)" do
      {:ok, ticket} = SupportTicket.create(%{priority: 4})
      {:ok, ticket} = SupportTicket.triage(ticket)
      assert ticket.state == :standard
    end

    test "priority 10 (maximum) goes to escalated" do
      {:ok, ticket} = SupportTicket.create(%{priority: 10})
      {:ok, ticket} = SupportTicket.triage(ticket)
      assert ticket.state == :escalated
    end

    test "priority 1 (minimum) goes to standard" do
      {:ok, ticket} = SupportTicket.create(%{priority: 1})
      {:ok, ticket} = SupportTicket.triage(ticket)
      assert ticket.state == :standard
    end
  end

  describe "ticket lifecycle" do
    test "standard ticket: new -> triage -> assign -> resolve -> close" do
      {:ok, ticket} = SupportTicket.create(%{title: "Help request", priority: 2})
      assert ticket.state == :new

      {:ok, ticket} = SupportTicket.triage(ticket)
      assert ticket.state == :standard

      {:ok, ticket} = SupportTicket.assign(ticket, %{assigned_to: "agent@example.com"})
      assert ticket.state == :in_progress
      assert ticket.assigned_to == "agent@example.com"

      {:ok, ticket} = SupportTicket.resolve(ticket)
      assert ticket.state == :resolved

      {:ok, ticket} = SupportTicket.close(ticket)
      assert ticket.state == :closed
    end

    test "high priority ticket workflow" do
      {:ok, ticket} = SupportTicket.create(%{title: "Urgent issue", priority: 7})

      {:ok, ticket} = SupportTicket.triage(ticket)
      assert ticket.state == :high_priority

      {:ok, ticket} = SupportTicket.assign(ticket, %{assigned_to: "senior@example.com"})
      assert ticket.state == :in_progress

      {:ok, ticket} = SupportTicket.resolve(ticket)
      assert ticket.state == :resolved

      {:ok, ticket} = SupportTicket.close(ticket)
      assert ticket.state == :closed
    end

    test "escalated ticket can be assigned directly" do
      {:ok, ticket} = SupportTicket.create(%{title: "Critical outage", priority: 10})

      {:ok, ticket} = SupportTicket.triage(ticket)
      assert ticket.state == :escalated

      {:ok, ticket} = SupportTicket.assign(ticket, %{assigned_to: "manager@example.com"})
      assert ticket.state == :in_progress
    end
  end

  describe "escalation from in_progress" do
    test "ticket can be escalated after being assigned" do
      {:ok, ticket} = SupportTicket.create(%{title: "Complex issue", priority: 3})

      {:ok, ticket} = SupportTicket.triage(ticket)
      assert ticket.state == :standard

      {:ok, ticket} = SupportTicket.assign(ticket, %{assigned_to: "agent@example.com"})
      assert ticket.state == :in_progress

      {:ok, ticket} = SupportTicket.escalate(ticket)
      assert ticket.state == :escalated
    end

    test "escalated ticket can still be resolved" do
      {:ok, ticket} = SupportTicket.create(%{priority: 3})

      {:ok, ticket} = SupportTicket.triage(ticket)
      {:ok, ticket} = SupportTicket.assign(ticket, %{assigned_to: "agent@example.com"})
      {:ok, ticket} = SupportTicket.escalate(ticket)
      assert ticket.state == :escalated

      {:ok, ticket} = SupportTicket.resolve(ticket)
      assert ticket.state == :resolved
    end
  end

  describe "reopening tickets" do
    test "resolved ticket can be reopened" do
      {:ok, ticket} = SupportTicket.create(%{priority: 3})

      {:ok, ticket} = SupportTicket.triage(ticket)
      {:ok, ticket} = SupportTicket.assign(ticket, %{})
      {:ok, ticket} = SupportTicket.resolve(ticket)
      assert ticket.state == :resolved

      {:ok, ticket} = SupportTicket.reopen(ticket)
      assert ticket.state == :in_progress
    end

    test "closed ticket can be reopened" do
      {:ok, ticket} = SupportTicket.create(%{priority: 3})

      {:ok, ticket} = SupportTicket.triage(ticket)
      {:ok, ticket} = SupportTicket.assign(ticket, %{})
      {:ok, ticket} = SupportTicket.resolve(ticket)
      {:ok, ticket} = SupportTicket.close(ticket)
      assert ticket.state == :closed

      {:ok, ticket} = SupportTicket.reopen(ticket)
      assert ticket.state == :in_progress
    end
  end

  describe "invalid transitions" do
    test "cannot triage already triaged ticket" do
      {:ok, ticket} = SupportTicket.create(%{priority: 3})
      {:ok, ticket} = SupportTicket.triage(ticket)
      assert ticket.state == :standard

      {:error, error} = SupportTicket.triage(ticket)
      assert Exception.message(error) =~ "triage"
    end

    test "cannot resolve ticket that is not in progress or escalated" do
      {:ok, ticket} = SupportTicket.create(%{priority: 3})
      {:ok, ticket} = SupportTicket.triage(ticket)
      assert ticket.state == :standard

      {:error, error} = SupportTicket.resolve(ticket)
      assert Exception.message(error) =~ "resolve"
    end

    test "cannot close ticket that is not resolved" do
      {:ok, ticket} = SupportTicket.create(%{priority: 3})
      {:ok, ticket} = SupportTicket.triage(ticket)
      {:ok, ticket} = SupportTicket.assign(ticket, %{})
      assert ticket.state == :in_progress

      {:error, error} = SupportTicket.close(ticket)
      assert Exception.message(error) =~ "close"
    end
  end
end
