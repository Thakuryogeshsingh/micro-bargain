from django.urls import path

from . import views

app_name = "growth"

urlpatterns = [
    path("alerts/", views.AlertListView.as_view(), name="alerts"),
    path("alerts/<int:pk>/", views.AlertDetailView.as_view(), name="alert"),
    path("shopping-list/", views.ShoppingListView.as_view(), name="shopping-list"),
    path("groups/", views.GroupNearbyView.as_view(), name="groups"),
    path("groups/start/", views.GroupStartView.as_view(), name="group-start"),
    path("groups/<int:pk>/join/", views.GroupJoinView.as_view(), name="group-join"),
    path("loyalty/", views.LoyaltyView.as_view(), name="loyalty"),
    path("campaigns/", views.CampaignListView.as_view(), name="campaigns"),
]
