from django.urls import path

from . import views

app_name = "reviews"

urlpatterns = [
    path("", views.MyReviewsView.as_view(), name="mine"),
    path("create/", views.ReviewCreateView.as_view(), name="create"),
    path("shop/<int:shop_id>/", views.ShopReviewsView.as_view(), name="shop"),
    path("<int:pk>/reply/", views.ReplyView.as_view(), name="reply"),
]
