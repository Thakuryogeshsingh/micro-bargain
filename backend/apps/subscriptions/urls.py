from django.urls import path

from . import views

app_name = "subscriptions"

urlpatterns = [
    path("plans/", views.PlanListView.as_view(), name="plans"),
    path("current/", views.CurrentPlanView.as_view(), name="current"),
    path("subscribe/", views.SubscribeView.as_view(), name="subscribe"),
    path("history/", views.SubscriptionHistoryView.as_view(), name="history"),
]
